import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { stitchFrames } from "./stitch";
import { sendEmailWithGif } from "./email";

admin.initializeApp();

export const onSessionWrite = onDocumentWritten("sessions/{sessionId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const data = snapshot.after.data();
  if (!data) return;

  const uploadedFrames = data.uploadedFrames || {};
  const frameKeys = Object.keys(uploadedFrames);
  const expectedFrames = data.expectedFrames || 5;

  // When all expected cameras have uploaded their frames, run the stitching flow
  if (frameKeys.length === expectedFrames && data.status === "uploading") {
    const db = admin.firestore();
    const docRef = db.collection("sessions").doc(event.params.sessionId);

    // Transition to processing state to avoid multiple executions
    await docRef.update({
      status: "processing",
      updatedAt: FieldValue.serverTimestamp(),
    });

    try {
      const gifUrl = await stitchFrames(event.params.sessionId, uploadedFrames);

      await docRef.update({
        status: "completed",
        gifUrl: gifUrl,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (err: any) {
      console.error(`[STITCH ERROR] Session ${event.params.sessionId} failed:`, err);
      await docRef.update({
        status: "failed",
        errorMessage: err.message || String(err),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }
});

export const sendGifEmail = onCall(async (request) => {
  const { sessionId, email, gifUrl } = request.data;

  if (!sessionId || !email || !gifUrl) {
    throw new HttpsError("invalid-argument", "Missing required fields: sessionId, email, gifUrl.");
  }

  const apiKey = process.env.RESEND_KEY || process.env.RESEND_API_KEY;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "Resend API key is not configured on the backend.");
  }

  const db = admin.firestore();
  const shareRef = db.collection("sessions").doc(sessionId).collection("shares").doc();

  await shareRef.set({
    id: shareRef.id,
    email: email,
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
  });

  try {
    await sendEmailWithGif(email, gifUrl, apiKey);

    await shareRef.update({
      status: "sent",
      sentAt: FieldValue.serverTimestamp(),
    });

    return { success: true };
  } catch (err: any) {
    console.error(`[EMAIL ERROR] Failed to send email to ${email}:`, err);
    await shareRef.update({
      status: "failed",
      errorMessage: err.message || String(err),
    });
    throw new HttpsError("internal", err.message || String(err));
  }
});
