/**
 * Decode GitHub Contents API JSON (base64 "content" field) to a UTF-8 file.
 * Usage: node decode-github-api-file.mjs <api-response.json> <outfile>
 */
import fs from "fs";

const [, , jsonPath, outPath] = process.argv;
if (!jsonPath || !outPath) {
  console.error("Usage: node decode-github-api-file.mjs <api-response.json> <outfile>");
  process.exit(1);
}
const j = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
const b64 = String(j.content || "").replace(/\s/g, "");
const buf = Buffer.from(b64, "base64");
fs.writeFileSync(outPath, buf);
console.log("Wrote", buf.length, "bytes ->", outPath);
