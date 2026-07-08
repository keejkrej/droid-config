#!/usr/bin/env node
// Non-destructively merges this repo's factory/{mcp,settings}.json templates
// into the live ~/.factory/*.json config, without touching unrelated keys the
// user (or the Factory CLI itself) may have added.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const [, , mode, templatePath, targetPath] = process.argv;

if (!mode || !templatePath || !targetPath) {
  console.error("Usage: merge-json.mjs <mcp|settings> <template.json> <target.json>");
  process.exit(1);
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const raw = fs.readFileSync(filePath, "utf8").trim();
  return raw ? JSON.parse(raw) : {};
}

// Expands the literal token "$HOME" inside string values so the template
// stays portable across machines/users.
function expandHome(value) {
  const home = os.homedir();
  if (typeof value === "string") return value.replaceAll("$HOME", home);
  if (Array.isArray(value)) return value.map(expandHome);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, expandHome(v)]));
  }
  return value;
}

const template = expandHome(readJson(templatePath));
const target = readJson(targetPath);

if (mode === "mcp") {
  target.mcpServers = target.mcpServers || {};
  for (const [name, cfg] of Object.entries(template.mcpServers || {})) {
    target.mcpServers[name] = cfg;
  }
} else if (mode === "settings") {
  target.customModels = target.customModels || [];
  for (const model of template.customModels || []) {
    const idx = target.customModels.findIndex((m) => m.id === model.id);
    if (idx >= 0) target.customModels[idx] = model;
    else target.customModels.push(model);
  }
  // Merge sessionDefaultSettings -- only set keys present in the template,
  // so user-tuned settings in the live file are preserved for keys we don't own.
  if (template.sessionDefaultSettings) {
    target.sessionDefaultSettings = target.sessionDefaultSettings || {};
    for (const [k, v] of Object.entries(template.sessionDefaultSettings)) {
      target.sessionDefaultSettings[k] = v;
    }
  }
} else {
  console.error(`Unknown mode "${mode}". Expected "mcp" or "settings".`);
  process.exit(1);
}

fs.mkdirSync(path.dirname(targetPath), { recursive: true });
fs.writeFileSync(targetPath, JSON.stringify(target, null, 2) + "\n");
console.log(`Updated ${targetPath}`);
