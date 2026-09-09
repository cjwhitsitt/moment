# Callable Function Contract: `sendGifEmail`

The `sendGifEmail` endpoint is a Firebase Cloud Functions v2 HTTPS Callable Function. It accepts session metadata and recipient details, verifies that the `RESEND_KEY` secret is mounted, and dispatches the email via Resend.

---

## 1. Secret Configuration

- **Secret Identifier**: `RESEND_KEY`
- **Cloud Provider**: Google Cloud Secret Manager (configured via `firebase functions:secrets:set RESEND_KEY`)
- **Local Emulation**: `functions/.secret.local`
- **Function Declaration**:
  ```typescript
  export const sendGifEmail = onCall({ secrets: ["RESEND_KEY"] }, async (request) => { ... });
  ```

---

## 2. Request Payload

Sent by the Flutter Operator App:

```json
{
  "data": {
    "sessionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "email": "guest@example.com",
    "gifUrl": "https://firebasestorage.googleapis.com/v0/b/moment-aad8b.firebasestorage.app/o/sessions%2F...%2Fstitched.gif?alt=media"
  }
}
```

### Parameters
- `sessionId` (string, required): Active photo booth session identifier.
- `email` (string, required): Valid email address of recipient.
- `gifUrl` (string, required): Public or signed URL of the stitched looping GIF.

---

## 3. Success Response

```json
{
  "result": {
    "success": true
  }
}
```

---

## 4. Error Responses

- **Invalid Arguments (HTTP 400)**:
  ```json
  {
    "error": {
      "message": "Missing required fields: sessionId, email, gifUrl.",
      "status": "INVALID_ARGUMENT"
    }
  }
  ```

- **Unconfigured Secret (HTTP 400)**:
  ```json
  {
    "error": {
      "message": "Resend API key is not configured on the backend.",
      "status": "FAILED_PRECONDITION"
    }
  }
  ```

- **Upstream Delivery Failure (HTTP 500)**:
  ```json
  {
    "error": {
      "message": "Resend email error: ...",
      "status": "INTERNAL"
    }
  }
  ```
