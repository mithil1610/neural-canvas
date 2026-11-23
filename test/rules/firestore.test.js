const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'neural-canvas-rules-test';

describe('Firestore Security Rules', () => {
  let testEnv;

  before(async () => {
    const rulesPath = path.resolve(__dirname, '../../firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: rules,
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  describe('User-Data Isolation', () => {
    it('prevents unauthenticated user from reading user profiles', async () => {
      const unauthedDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(unauthedDb.collection('users').doc('alice').get());
    });

    it('prevents user A from reading user B profile', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(aliceDb.collection('users').doc('bob').get());
    });

    it('prevents user A from writing to user B profile', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('bob').set({
          fullName: 'Hacked by Alice',
        })
      );
    });

    it('prevents user A from accessing user B subcollections', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('bob').collection('knowledge_base').get()
      );
      await assertFails(
        aliceDb.collection('users').doc('bob').collection('knowledge_base').add({
          title: 'Secret',
        })
      );
    });

    it('allows user A to read and write own profile (without server fields)', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertSucceeds(
        aliceDb.collection('users').doc('alice').set({
          fullName: 'Alice In Wonderland',
          email: 'alice@example.com',
        })
      );
      await assertSucceeds(aliceDb.collection('users').doc('alice').get());
    });

    it('allows user A to read and write own subcollections', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertSucceeds(
        aliceDb.collection('users').doc('alice').collection('knowledge_base').add({
          title: 'My Notes',
          fileType: 'pdf',
        })
      );
    });
  });

  describe('Server-Protected Fields Enforcement', () => {
    it('prevents client from setting accountTier on creation', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').set({
          fullName: 'Alice',
          accountTier: 'Infinite Brain',
        })
      );
    });

    it('prevents client from setting tier on creation', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').set({
          fullName: 'Alice',
          tier: 'pro',
        })
      );
    });

    it('prevents client from setting aiUsageCount on creation', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').set({
          fullName: 'Alice',
          aiUsageCount: 0,
        })
      );
    });

    it('prevents client from setting dailyUploadCount on creation', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').set({
          fullName: 'Alice',
          dailyUploadCount: 0,
        })
      );
    });

    it('prevents client from setting lastUploadDate on creation', async () => {
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').set({
          fullName: 'Alice',
          lastUploadDate: '2026-11-22',
        })
      );
    });

    it('prevents client from modifying accountTier on update', async () => {
      // Seed document via admin context (bypasses security rules)
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('alice').set({
          fullName: 'Alice',
          accountTier: 'Free',
          dailyUploadCount: 1,
        });
      });

      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').update({
          accountTier: 'Infinite Brain',
        })
      );
    });

    it('prevents client from modifying dailyUploadCount on update', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('alice').set({
          fullName: 'Alice',
          dailyUploadCount: 1,
        });
      });

      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        aliceDb.collection('users').doc('alice').update({
          dailyUploadCount: 0,
        })
      );
    });

    it('prevents client from resetting chat and AI counters', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('alice').set({
          fullName: 'Alice',
          dailyChatCount: 30,
          lastChatDate: '2026-11-22',
          dailyAiOpsCount: 80,
        });
      });
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(aliceDb.collection('users').doc('alice').update({ dailyChatCount: 0 }));
      await assertFails(aliceDb.collection('users').doc('alice').update({ lastChatDate: '2000-01-01' }));
      await assertFails(aliceDb.collection('users').doc('alice').update({ dailyAiOpsCount: 0 }));
    });

    it('prevents client from deleting its profile document (quota reset)', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('alice').set({ fullName: 'Alice', dailyUploadCount: 10 });
      });
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertFails(aliceDb.collection('users').doc('alice').delete());
    });

    it('still allows client to delete its own vault items', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('alice').collection('knowledge_base').doc('k1').set({ title: 'x' });
      });
      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertSucceeds(aliceDb.collection('users').doc('alice').collection('knowledge_base').doc('k1').delete());
    });

    it('allows client to update non-protected fields like displayName', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('alice').set({
          fullName: 'Alice',
          accountTier: 'Free',
        });
      });

      const aliceDb = testEnv.authenticatedContext('alice').firestore();
      await assertSucceeds(
        aliceDb.collection('users').doc('alice').update({
          fullName: 'Alice Cooper',
        })
      );
    });
  });
});
