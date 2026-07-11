import * as admin from "firebase-admin";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import { exec } from "child_process";
import * as crypto from "crypto";

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
 * Parses the JPEG file binary stream to extract physical image dimensions
 * from the SOF (Start of Frame) segment. Avoids external binary dependencies.
 */
function getJpegDimensions(filePath: string): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    fs.open(filePath, "r", (err, fd) => {
      if (err) return reject(err);
      
      const buffer = Buffer.alloc(4);
      let offset = 2; // Skip SOI (FF D8)
      
      const readNext = () => {
        fs.read(fd, buffer, 0, 2, offset, (err, bytesRead) => {
          if (err || bytesRead < 2) {
            fs.closeSync(fd);
            return reject(err || new Error("EOF before dimensions found"));
          }
          
          if (buffer[0] !== 0xFF) {
            fs.closeSync(fd);
            return reject(new Error("Invalid JPEG marker"));
          }
          
          const marker = buffer[1];
          if (marker === 0xDA || marker === 0xD9) { // SOS or EOI
            fs.closeSync(fd);
            return reject(new Error("SOS reached before SOF"));
          }
          
          // SOF (Start of Frame) markers
          if ((marker >= 0xC0 && marker <= 0xC7 && marker !== 0xC4) || 
              (marker >= 0xC9 && marker <= 0xCF && marker !== 0xCC)) {
            const sofBuffer = Buffer.alloc(7);
            fs.read(fd, sofBuffer, 0, 7, offset + 2, (err, bytesRead) => {
              fs.closeSync(fd);
              if (err || bytesRead < 7) return reject(err || new Error("Failed to read SOF block"));
              
              const height = sofBuffer.readUInt16BE(3);
              const width = sofBuffer.readUInt16BE(5);
              resolve({ width, height });
            });
          } else {
            // Read length of this segment to skip it
            const lenBuffer = Buffer.alloc(2);
            fs.read(fd, lenBuffer, 0, 2, offset + 2, (err, bytesRead) => {
              if (err || bytesRead < 2) {
                fs.closeSync(fd);
                return reject(err || new Error("Failed to read segment length"));
              }
              const length = lenBuffer.readUInt16BE(0);
              offset += 2 + length;
              readNext();
            });
          }
        });
      };
      
      readNext();
    });
  });
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

    // Detect orientation of the first frame using ffprobe
    const firstFramePath = cameraMap.get(1);
    let isPortrait = false;
    if (firstFramePath) {
      try {
        const dims = await getJpegDimensions(firstFramePath);
        isPortrait = dims.height > dims.width;
        console.log(`[STITCH] Detected orientation: ${isPortrait ? "Portrait" : "Landscape"} (${dims.width}x${dims.height})`);
      } catch (e) {
        console.error(`[STITCH] Orientation detection failed:`, e);
      }
    }

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

    const filter = isPortrait
      ? "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)',scale=450:800"
      : "crop=w='min(iw,ih*16/9)':h='min(ih,iw*9/16)',scale=800:450";

    for (let seqIndex = 0; seqIndex < sequence.length; seqIndex++) {
      const camIndex = sequence[seqIndex];
      const srcPath = cameraMap.get(camIndex);
      if (!srcPath) {
        throw new Error(`Missing download for camera index ${camIndex}`);
      }
      const destPath = path.join(sessionDir, `frame_${seqIndex}.jpg`);
      
      // Center-crop and scale to 16:9/9:16 aspect ratio using FFmpeg
      const preScaleCmd = `"${ffmpegPath}" -y -i "${srcPath}" -vf "${filter}" "${destPath}"`;
      await new Promise<void>((resolve, reject) => {
        exec(preScaleCmd, (error) => {
          if (error) reject(error);
          else resolve();
        });
      });
    }

    // 3. Compile high-quality GIF using palettegen and paletteuse
    const outputGifPath = path.join(sessionDir, "output.gif");
    const ffmpegCmd = `"${ffmpegPath}" -y -reinit_filter 0 -f image2 -start_number 0 -framerate 10 -i "${sessionDir}/frame_%d.jpg" -filter_complex "split [a][b];[a] palettegen [p];[b][p] paletteuse" "${outputGifPath}"`;

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

    // 4. Upload GIF with cache control headers and a Firebase download token
    const destStoragePath = `stitched/${sessionId}.gif`;
    const downloadToken = crypto.randomUUID();
    await bucket.upload(outputGifPath, {
      destination: destStoragePath,
      metadata: {
        contentType: "image/gif",
        cacheControl: "public, max-age=31536000",
        metadata: {
          firebaseStorageDownloadTokens: downloadToken,
        },
      },
    });

    // 5. Get public firebase download url to display to guests
    let url: string;
    if (process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
      url = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${bucket.name}/o/${encodeURIComponent(destStoragePath)}?alt=media`;
    } else {
      url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(destStoragePath)}?alt=media&token=${downloadToken}`;
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
