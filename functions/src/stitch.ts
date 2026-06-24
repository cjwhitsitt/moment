import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import { exec } from "child_process";

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

    // 2. Sequence frames as 1-2-3-4-5-4-3-2 (seamless loop)
    const sequence = [1, 2, 3, 4, 5, 4, 3, 2];
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
    const ffmpegCmd = `ffmpeg -y -f image2 -framerate 10 -i "${sessionDir}/frame_%d.jpg" -filter_complex "[0:v] split [a][b];[a] palettegen [p];[b][p] paletteuse" "${outputGifPath}"`;

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
    const [url] = await file.getSignedUrl({
      action: "read",
      expires: "01-01-2099",
    });

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
