const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();
const db = admin.firestore();

// API Key should ideally be in Secret Manager
const API_KEY = process.env.GEMINI_API_KEY || "TODO_YOUR_API_KEY_HERE";
const genAI = new GoogleGenerativeAI(API_KEY);

const DAILY_LIMIT = 20;

exports.analyzeMedia = onCall(async (request) => {
  // 1. Enforce absolute user authentication
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be logged in to access Neural Canvas AI."
    );
  }

  const uid = request.auth.uid;
  const prompt = request.data.prompt;
  const mediaPath = request.data.mediaPath;
  const mediaType = request.data.mediaType;

  if (!prompt) {
    throw new HttpsError("invalid-argument", "Missing 'prompt' in request.");
  }

  // 2. Read the user's document profile from Firestore
  const userRef = db.collection("users").doc(uid);
  
  // Use a transaction to safely read and increment the usage counter
  const resultText = await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const today = new Date().toISOString().split("T")[0];
    
    let dailyUsage = 0;
    let tier = "free"; // Default tier
    
    if (userDoc.exists) {
      const data = userDoc.data();
      tier = data.tier || "free";
      if (data.lastUsageDate === today) {
        dailyUsage = data.dailyUsage || 0;
      }
    }

    // Evaluate tier configuration
    const dailyLimit = tier === "pro" ? 100 : 15;
    const modelName = tier === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash-lite";

    if (dailyUsage >= dailyLimit) {
      throw new HttpsError(
        "resource-exhausted",
        `You have reached your daily limit of ${dailyLimit} requests for the ${tier} tier. Please try again tomorrow or upgrade.`
      );
    }

    // 4. Pass the multimodal payloads to the Gemini model execution thread
    try {
      const model = genAI.getGenerativeModel({ 
          model: modelName,
          systemInstruction: "You are the Neural Canvas Digital Memory Assistant..."
      });

      let contentParts = [prompt];

      // If a file was attached, download it securely from Firebase Storage
      if (mediaPath && mediaType) {
        const bucket = admin.storage().bucket();
        const file = bucket.file(mediaPath);
        
        // Ensure the file belongs to this user!
        if (!mediaPath.startsWith(`uploads/${uid}/`)) {
           throw new HttpsError("permission-denied", "You can only process your own files.");
        }

        const [buffer] = await file.download();
        
        contentParts.push({
          inlineData: {
            data: buffer.toString("base64"),
            mimeType: mediaType
          }
        });

        // Clean up the temporary file immediately after downloading
        await file.delete().catch(console.error);
      }

      const aiResponse = await model.generateContent(contentParts);
      const outputText = aiResponse.response.text();

      // 5. Increment the user's daily usage count
      transaction.set(userRef, {
        tier: tier, // Preserve tier configuration
        dailyUsage: dailyUsage + 1,
        lastUsageDate: today
      }, { merge: true });

      // Track granular daily usage for analytics (Optional but explicitly requested)
      const usageTrackingRef = userRef.collection('usage').doc(today);
      transaction.set(usageTrackingRef, {
         count: admin.firestore.FieldValue.increment(1),
         lastRequestTime: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      return outputText;
    } catch (error) {
      console.error("Gemini Error:", error);
      throw new HttpsError("internal", "Failed to communicate with Neural Core.");
    }
  });

  return { response: resultText };
});
