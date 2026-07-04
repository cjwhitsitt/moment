import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import { exec } from "child_process";

let ffmpegPath = "ffmpeg";
try {
  const ffmpegInstaller = require("@ffmpeg-installer/ffmpeg");
  ffmpegPath = ffmpegInstaller.path;
} catch (e) {
  // Graceful fallback for local development (e.g. Apple Silicon Mac)
  if (process.platform === "darwin") {
    if (fs.existsSync("/opt/homebrew/bin/ffmpeg")) {
      ffmpegPath = "/opt/homebrew/bin/ffmpeg";
    } else if (fs.existsSync("/usr/local/bin/ffmpeg")) {
      ffmpegPath = "/usr/local/bin/ffmpeg";
    }
  }
  console.log(`[FFMPEG] Fallback configured to use executable at: "${ffmpegPath}"`);
}

/**
 * Downloads the 5 raw smartphone capture frames, sequences them as 1-2-3-4-5-4-3-2,
 * executes FFmpeg with dynamic palette generation for premium GIF quality,
 * and uploads the final GIF back to Firebase Storage.
 */
export async function stitchFrames(
  sessionId: string,
  uploadedFrames: { [key: string]: string }
): Promise<string> {
  const tempDir = os.tmpdir();
  const sessionDir = path.join(tempDir, sessionId);
  fs.mkdirSync(sessionDir, { recursive: true });

  const bucket = admin.storage().bucket();

  try {
    // 1. Download raw frames concurrently
    const downloadPromises = Object.entries(uploadedFrames).map(async ([indexStr, storagePath]) => {
      const localPath = path.join(sessionDir, `cam${indexStr}.jpg`);
      await bucket.file(storagePath).download({ destination: localPath });
      return { index: parseInt(indexStr), localPath };
    });

    const downloaded = await Promise.all(downloadPromises);
    const cameraMap = new Map<number, string>();
    downloaded.forEach((item) => cameraMap.set(item.index, item.localPath));

    // 2. Sequence frames dynamically in a ping-pong pattern (e.g., 1 -> 2 -> ... -> N -> N-1 -> ... -> 2)
    const numFrames = Object.keys(uploadedFrames).length;
    if (numFrames < 3) {
      throw new Error(`Too few frames to stitch a ping-pong loop (expected at least 3, got ${numFrames})`);
    }

    const sequence: number[] = [];
    for (let i = 1; i <= numFrames; i++) {
      sequence.push(i);
    }
    for (let i = numFrames - 1; i > 1; i--) {
      sequence.push(i);
    }

    sequence.forEach((camIndex, seqIndex) => {
      const srcPath = cameraMap.get(camIndex);
      if (!srcPath) {
        throw new Error(`Missing download for camera index ${camIndex}`);
      }
      const destPath = path.join(sessionDir, `frame_${seqIndex}.jpg`);
      fs.copyFileSync(srcPath, destPath);
    });

    // 3. Compile high-quality GIF using palettegen and paletteuse
    const outputGifPath = path.join(sessionDir, "output.gif");
    const ffmpegCmd = `"${ffmpegPath}" -y -reinit_filter 0 -f image2 -start_number 0 -framerate 10 -i "${sessionDir}/frame_%d.jpg" -filter_complex "[0:v] scale=800:600:force_original_aspect_ratio=decrease,pad=800:600:(ow-iw)/2:(oh-ih)/2,split [a][b];[a] palettegen [p];[b] fifo [v];[v][p] paletteuse" "${outputGifPath}"`;

    await new Promise<void>((resolve, reject) => {
      exec(ffmpegCmd, (error, stdout, stderr) => {
        if (error) {
          console.error("FFmpeg execution error details:", stderr);
          reject(error);
        } else {
          resolve();
        }
      });
    });

    // 4. Upload GIF with cache control headers
    const destStoragePath = `stitched/${sessionId}.gif`;
    const [file] = await bucket.upload(outputGifPath, {
      destination: destStoragePath,
      metadata: {
        contentType: "image/gif",
        cacheControl: "public, max-age=31536000",
      },
    });

    // 5. Get far-future signed url to display to guests
    let url: string;
    if (process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
      url = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${bucket.name}/o/${encodeURIComponent(destStoragePath)}?alt=media`;
    } else {
      const [signedUrl] = await file.getSignedUrl({
        action: "read",
        expires: "01-01-2099",
      });
      url = signedUrl;
    }

    return url;
  } finally {
    // 6. Clean up temporary local directory
    try {
      fs.rmSync(sessionDir, { recursive: true, force: true });
    } catch (e) {
      console.warn("Failed to clean up temporary stitching directory:", e);
    }
  }
}
