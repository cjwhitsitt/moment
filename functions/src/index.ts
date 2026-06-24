import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { stitchFrames } from "./stitch";

admin.initializeApp();

export const onSessionWrite = onDocumentWritten("sessions/{sessionId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const data = snapshot.after.data();
  if (!data) return;

  const uploadedFrames = data.uploadedFrames || {};
  const frameKeys = Object.keys(uploadedFrames);

  // When all 5 cameras have uploaded their frames, run the stitching flow
  if (frameKeys.length === 5 && data.status === "uploading") {
    const db = admin.firestore();
    const docRef = db.collection("sessions").doc(event.params.sessionId);

    // Transition to processing state to avoid multiple executions
    await docRef.update({
      status: "processing",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      const gifUrl = await stitchFrames(event.params.sessionId, uploadedFrames);

      await docRef.update({
        status: "completed",
        gifUrl: gifUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err: any) {
      console.error(`[STITCH ERROR] Session ${event.params.sessionId} failed:`, err);
      await docRef.update({
        status: "failed",
        errorMessage: err.message || String(err),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
});
