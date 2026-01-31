"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const pika2c = path.join(root, "build", "pika2c");
const runtimePath = path.join(root, "lib", "javascript", "runtime.js");
const testDir = path.join(root, "test", "pika");

if (!fs.existsSync(pika2c)) {
	console.error("Missing build/pika2c. Run `make pika2c` first.");
	process.exit(2);
}
if (!fs.existsSync(runtimePath)) {
	console.error("Missing lib/javascript/runtime.js.");
	process.exit(2);
}

const runtime = fs.readFileSync(runtimePath, "utf8");
const tests = fs
	.readdirSync(testDir, { withFileTypes: true })
	.filter((entry) => entry.isFile() && entry.name.endsWith(".pka"))
	.map((entry) => path.join(testDir, entry.name))
	.sort();

let pass = 0;
let fail = 0;

function runTest(name, src, injectJs) {
	process.stdout.write(`Testing ${name}... `);
	const input = `-T js\n${src}`;
	const transpile = spawnSync(pika2c, [], {
		input,
		encoding: "utf8",
		maxBuffer: 50 * 1024 * 1024,
	});

	if (transpile.status !== 0) {
		fail += 1;
		console.log("FAIL (transpile)");
		if (transpile.stderr) {
			process.stdout.write(transpile.stderr);
		}
		return;
	}

	const jsPath = path.join(os.tmpdir(), `pika_js_${name}_${process.pid}.js`);
	const injected = injectJs ? `${injectJs}\n` : "";
	fs.writeFileSync(jsPath, `${runtime}\n${injected}${transpile.stdout}`, "utf8");

	const run = spawnSync(process.execPath, [jsPath], {
		encoding: "utf8",
		maxBuffer: 10 * 1024 * 1024,
	});

	if (run.status === 0) {
		pass += 1;
		console.log("PASS");
		fs.unlinkSync(jsPath);
	} else {
		fail += 1;
		console.log("FAIL (runtime)");
		if (run.stderr) {
			process.stdout.write(run.stderr);
		}
		console.log(`JS output kept at ${jsPath}`);
	}
}

function transpileWithBinary(name, input) {
	process.stdout.write(`Testing ${name}... `);
	const transpile = spawnSync(pika2c, [], {
		input,
		encoding: "utf8",
		maxBuffer: 50 * 1024 * 1024,
	});

	if (transpile.status !== 0) {
		fail += 1;
		console.log("FAIL (transpile)");
		if (transpile.stderr) {
			process.stdout.write(transpile.stderr);
		}
		return null;
	}

	pass += 1;
	console.log("PASS");
	return transpile.stdout;
}

function transpileWithJs(name, jsSrc, input) {
	process.stdout.write(`Testing ${name}... `);
	const safeName = name.replace(/[^a-z0-9_-]+/gi, "_");
	const jsPath = path.join(os.tmpdir(), `pika_js_${safeName}_${process.pid}.js`);
	fs.writeFileSync(jsPath, `${runtime}\n${jsSrc}`, "utf8");

	const run = spawnSync(process.execPath, [jsPath], {
		input,
		encoding: "utf8",
		maxBuffer: 50 * 1024 * 1024,
	});

	if (run.status === 0) {
		pass += 1;
		console.log("PASS");
		fs.unlinkSync(jsPath);
		return run.stdout;
	}

	fail += 1;
	console.log("FAIL (runtime)");
	if (run.stderr) {
		process.stdout.write(run.stderr);
	}
	console.log(`JS output kept at ${jsPath}`);
	return null;
}

const externSrc = [
	"use rt;",
	"",
	"@symbol(\"jsfactorial\") fn factorial(x: i64) i64;",
	"",
	"export fn main() void = {",
	"\tlet v = factorial(10);",
	"\tassert(v == 3628800);",
	"};",
].join("\n");

const externJs = [
	"function jsfactorial(x) {",
	"\tlet v = 1;",
	"\tfor (let i = 2; i <= x; i += 1) {",
	"\t\tv *= i;",
	"\t}",
	"\treturn v;",
	"}",
].join("\n");

runTest("extern_jsfactorial", externSrc, externJs);

for (const file of tests) {
	const name = path.basename(file, ".pka");
	const src = fs.readFileSync(file, "utf8");
	runTest(name, src, null);
}

const pika2cDir = path.join(root, "cmd", "pika2c");
const pika2cSources = fs
	.readdirSync(pika2cDir, { withFileTypes: true })
	.filter((entry) => entry.isFile() && entry.name.endsWith(".pka"))
	.map((entry) => path.join(pika2cDir, entry.name))
	.sort()
	.map((file) => fs.readFileSync(file, "utf8"))
	.join("");
const selfInput = `-T js\n${pika2cSources}`;

console.log("");
console.log("=== pika2c JS Self-Hosting Tests ===");
const gen1 = transpileWithBinary("js gen1 (pika2c -> js)", selfInput);
const gen2 = gen1
	? transpileWithJs("js gen2 (gen1 -> js)", gen1, selfInput)
	: null;
const gen3 = gen2
	? transpileWithJs("js gen3 (gen2 -> js)", gen2, selfInput)
	: null;

process.stdout.write("Testing js fixed-point (gen2 == gen3)... ");
if (gen2 === null || gen3 === null) {
	fail += 1;
	console.log("FAIL (missing generation)");
} else if (gen2 === gen3) {
	pass += 1;
	console.log("PASS");
} else {
	fail += 1;
	console.log("FAIL (output differs)");
}

console.log("");
console.log(`Summary: Passed: ${pass} Failed: ${fail} Total: ${pass + fail}`);
process.exit(fail === 0 ? 0 : 1);
