import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const expectedDocs = [
  "arquitectura.md",
  "despliegue.md",
  "gobierno.md",
  "integracion.md",
  "modelo-economico.md",
  "modelo-seguridad.md",
  "operaciones.md",
];

test("release metadata fixes the production toolchain", async () => {
  const packageJson = JSON.parse(await readFile("package.json", "utf8"));
  const foundry = await readFile("foundry.toml", "utf8");
  const workflow = await readFile(".github/workflows/ci.yml", "utf8");
  assert.equal(packageJson.version, "1.0.0");
  assert.match(foundry, /solc_version = "0\.8\.24"/);
  assert.match(workflow, /version: v1\.7\.1/);
  assert.match(workflow, /forge-std@v1\.16\.2/);
  assert.match(workflow, /node-version: "24"/);
});

test("documentation set contains the required diagrams", async () => {
  const files = (await readdir("docs")).filter((file) => file.endsWith(".md")).sort();
  assert.deepEqual(files, expectedDocs);
  const contents = await Promise.all(files.map((file) => readFile(`docs/${file}`, "utf8")));
  assert.ok(contents.filter((content) => content.includes("```mermaid")).length >= 5);
});

test("banner uses the canonical canvas", async () => {
  const banner = await readFile("assets/banner.png");
  assert.deepEqual(banner.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  assert.equal(banner.readUInt32BE(16), 1672);
  assert.equal(banner.readUInt32BE(20), 941);
});
