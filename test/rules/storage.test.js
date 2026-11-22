const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'neural-canvas-storage-rules-test';

describe('Storage Security Rules', () => {
  let testEnv;

  before(async () => {
    const rulesPath = path.resolve(__dirname, '../../storage.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      storage: {
        rules: rules,
        host: '127.0.0.1',
        port: 9199,
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    await testEnv.clearStorage();
  });

  it('prevents unauthenticated user from reading/writing storage', async () => {
    const unauthedStorage = testEnv.unauthenticatedContext().storage();
    const fileRef = unauthedStorage.ref('users/alice/uploads/photo.jpg');
    await assertFails(fileRef.getDownloadURL());
    await assertFails(fileRef.put(Buffer.from('test'), { contentType: 'image/jpeg' }));
  });

  it('prevents user A from reading user B files', async () => {
    const aliceStorage = testEnv.authenticatedContext('alice').storage();
    const bobFileRef = aliceStorage.ref('users/bob/uploads/secret.pdf');
    await assertFails(bobFileRef.getDownloadURL());
  });

  it('prevents user A from uploading to user B directory', async () => {
    const aliceStorage = testEnv.authenticatedContext('alice').storage();
    const bobFileRef = aliceStorage.ref('users/bob/uploads/malicious.pdf');
    await assertFails(
      bobFileRef.put(Buffer.from('hello'), { contentType: 'application/pdf' })
    );
  });

  it('allows user A to upload valid image to own directory', async () => {
    const aliceStorage = testEnv.authenticatedContext('alice').storage();
    const fileRef = aliceStorage.ref('users/alice/uploads/photo.jpg');
    await assertSucceeds(
      fileRef.put(Buffer.from('image-bytes'), { contentType: 'image/jpeg' })
    );
  });

  it('allows user A to upload valid PDF and text files to own directory', async () => {
    const aliceStorage = testEnv.authenticatedContext('alice').storage();
    const pdfRef = aliceStorage.ref('users/alice/knowledge_base/document.pdf');
    await assertSucceeds(
      pdfRef.put(Buffer.from('%PDF-1.4...'), { contentType: 'application/pdf' })
    );

    const txtRef = aliceStorage.ref('users/alice/knowledge_base/note.txt');
    await assertSucceeds(
      txtRef.put(Buffer.from('hello notes'), { contentType: 'text/plain' })
    );
  });

  it('allows user A to upload Word document to own directory', async () => {
    const aliceStorage = testEnv.authenticatedContext('alice').storage();
    const docRef = aliceStorage.ref('users/alice/knowledge_base/document.docx');
    await assertSucceeds(
      docRef.put(Buffer.from('docx-bytes'), {
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      })
    );
  });

  it('prevents upload of disallowed mime types', async () => {
    const aliceStorage = testEnv.authenticatedContext('alice').storage();
    const zipRef = aliceStorage.ref('users/alice/uploads/archive.zip');
    await assertFails(
      zipRef.put(Buffer.from('zip-content'), { contentType: 'application/zip' })
    );

    const exeRef = aliceStorage.ref('users/alice/uploads/malware.exe');
    await assertFails(
      exeRef.put(Buffer.from('binary'), { contentType: 'application/octet-stream' })
    );
  });
});
