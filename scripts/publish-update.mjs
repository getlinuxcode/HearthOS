#!/usr/bin/env node
// Publie une mise à jour de Hearth (interface + service), installable depuis la console sans ISO.
//
//   node scripts/publish-update.mjs --version 0.2.1 --notes "Nouveautés…"   → prépare out/updates/
//   … --publish                     → crée la release GitHub vX.Y.Z (gh) avec manifest.json + archive
//   … --base http://<IP du PC>:8787 --serve → sert out/updates/ sur le réseau local (tests en VM)
//
// La clé privée de signature est lue dans ~/.hearth/update-signing-key.pem (ou HEARTH_SIGNING_KEY).
// Sans elle, impossible de publier : la console refuse toute archive non signée par cette clé.
import { execFileSync, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO = 'getlinuxcode/HearthOS';
const args = Object.fromEntries(
  process.argv.slice(2).map((a, i, all) => (a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : [])).filter((x) => x.length),
);

const sh = (cmd, argv, opts = {}) => execFileSync(cmd, argv, { stdio: 'inherit', shell: process.platform === 'win32', ...opts });
const step = (m) => console.log(`\n==> ${m}`);

// ---------------------------------------------------------------- Version
const versionFile = path.join(ROOT, 'VERSION');
let version = fs.readFileSync(versionFile, 'utf8').trim();
if (typeof args.version === 'string') {
  version = args.version;
  fs.writeFileSync(versionFile, version + '\n');
}
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`Version invalide : ${version} (attendu X.Y.Z)`);
const notes = typeof args.notes === 'string' ? args.notes : `Hearth ${version}`;

const keyPath = process.env.HEARTH_SIGNING_KEY ?? path.join(os.homedir(), '.hearth', 'update-signing-key.pem');
if (!fs.existsSync(keyPath)) {
  console.error(`Clé de signature introuvable : ${keyPath}\nCopiez-la depuis le PC du mainteneur (elle ne doit jamais être versionnée).`);
  process.exit(1);
}

// ---------------------------------------------------------------- Construction
step(`Compilation du service (version ${version})`);
sh('npm', ['run', 'build', '-w', 'daemon'], { cwd: ROOT });

const OUT = path.join(ROOT, 'out', 'updates');
const STAGE = path.join(ROOT, 'out', 'stage', version);
fs.rmSync(STAGE, { recursive: true, force: true });
fs.mkdirSync(path.join(STAGE, 'daemon'), { recursive: true });
fs.mkdirSync(OUT, { recursive: true });

step('Assemblage du paquet');
fs.copyFileSync(versionFile, path.join(STAGE, 'VERSION'));
fs.cpSync(path.join(ROOT, 'console'), path.join(STAGE, 'console'), {
  recursive: true,
  filter: (src) => !/[\\/](\.godot|tools)([\\/]|$)/.test(path.relative(ROOT, src)),
});
fs.cpSync(path.join(ROOT, 'daemon', 'dist'), path.join(STAGE, 'daemon', 'dist'), { recursive: true });
fs.copyFileSync(path.join(ROOT, 'daemon', 'package.json'), path.join(STAGE, 'daemon', 'package.json'));
sh('npm', ['install', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error'], { cwd: path.join(STAGE, 'daemon') });

step('Archive');
const archiveName = `hearth-${version}.tar.gz`;
const archive = path.join(OUT, archiveName);
const tar = process.platform === 'win32' ? 'C:\\Windows\\System32\\tar.exe' : 'tar';
const t = spawnSync(tar, ['-czf', archive, '.'], { cwd: STAGE, stdio: 'inherit' });
if (t.status !== 0) throw new Error('Création de l’archive impossible');
const data = fs.readFileSync(archive);
const sha256 = crypto.createHash('sha256').update(data).digest('hex');

step('Signature Ed25519');
const payload = Buffer.from(`hearth-update\n${version}\n${sha256}\n`);
const signature = crypto.sign(null, payload, crypto.createPrivateKey(fs.readFileSync(keyPath))).toString('base64');

const lanBase = typeof args.base === 'string' ? args.base.replace(/\/$/, '') : null;
const manifest = {
  version,
  url: lanBase ? `${lanBase}/${archiveName}` : `https://github.com/${REPO}/releases/download/v${version}/${archiveName}`,
  sha256,
  size: data.length,
  signature,
  notes,
  date: new Date().toISOString(),
};
fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 2));
console.log(`\n${archiveName}  ${(data.length / 1048576).toFixed(1)} Mo  sha256 ${sha256.slice(0, 16)}…`);

// ---------------------------------------------------------------- Publication
if (args.publish) {
  step(`Release GitHub v${version} sur ${REPO}`);
  sh('gh', ['release', 'create', `v${version}`, archive, path.join(OUT, 'manifest.json'), '--repo', REPO, '--title', `Hearth ${version}`, '--notes', notes]);
  console.log(`\nPubliée. Les consoles la proposeront dans Réglages → Système → Mises à jour.`);
}

if (args.serve) {
  const port = 8787;
  http
    .createServer((req, res) => {
      const f = path.join(OUT, path.basename(decodeURIComponent(req.url ?? '/')));
      if (!fs.existsSync(f) || !fs.statSync(f).isFile()) return res.writeHead(404).end();
      res.writeHead(200, { 'content-length': fs.statSync(f).size, 'content-type': f.endsWith('.json') ? 'application/json' : 'application/gzip' });
      fs.createReadStream(f).pipe(res);
    })
    .listen(port, '0.0.0.0', () => console.log(`\nCanal local : http://<IP de ce PC>:${port}/manifest.json (VirtualBox 7 bloque 10.0.2.2 : utilisez l'IP du PC)`));
}
