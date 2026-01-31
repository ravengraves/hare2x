"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const pika2c = path.join(root, "build", "pika2c");
const preludePath = path.join(root, "glsl", "gl.pka");
const vertPath = path.join(root, "test", "glsl", "003_demo_vertex.pka");
const fragPath = path.join(root, "test", "glsl", "003_demo_fragment.pka");
const demoTemplatePath = path.join(root, "wasm", "pika2glsl.html");

if (!fs.existsSync(pika2c)) {
	console.error("Missing build/pika2c. Run `make pika2c` first.");
	process.exit(2);
}
if (!fs.existsSync(preludePath)) {
	console.error("Missing glsl/gl.pka.");
	process.exit(2);
}
if (!fs.existsSync(demoTemplatePath)) {
	console.error("Missing wasm/pika2glsl.html.");
	process.exit(2);
}

const prelude = fs.readFileSync(preludePath, "utf8");

function compileStage(stage, source) {
	const input = `-T glsl\n-S ${stage}\n${source}\n${prelude}`;
	return spawnSync(pika2c, [], {
		input,
		encoding: "utf8",
		maxBuffer: 10 * 1024 * 1024,
	});
}

let fail = 0;

function runTest(name, stage, filePath) {
	process.stdout.write(`Testing ${name}... `);
	const source = fs.readFileSync(filePath, "utf8");
	const result = compileStage(stage, source);
	if (result.status === 0) {
		console.log("PASS");
		return;
	}
	fail += 1;
	console.log("FAIL");
	if (result.stderr) {
		process.stdout.write(result.stderr);
	}
}

runTest("demo_vertex", "vertex", vertPath);
runTest("demo_fragment", "fragment", fragPath);
process.stdout.write("Testing demo_template... ");
const template = fs.readFileSync(demoTemplatePath, "utf8");
if (template.includes("<GLSL_VERTEX_DEMO>") &&
	template.includes("<GLSL_FRAGMENT_DEMO>") &&
	template.includes("<GL_PK>")) {
	console.log("PASS");
} else {
	fail += 1;
	console.log("FAIL");
}

const total = 3;
console.log("");
console.log(`Summary: Failed: ${fail} Total: ${total}`);
process.exit(fail === 0 ? 0 : 1);
