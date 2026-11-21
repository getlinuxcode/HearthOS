import { MOCK } from '../config.js';
import type { Disk, Partition } from '../types.js';
import { run, runRoot } from '../util.js';

const GB = 1024 ** 3;
const ESP_GUID = 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b';
const MS_BASIC_GUID = 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7';
const SAFETY_MARGIN = 30 * GB; // espace laissé à Windows en plus de l'occupé

const mockDisks: Disk[] = [
  {
    path: '/dev/nvme0n1',
    model: 'Samsung SSD 980 PRO 1TB',
    size: 931.5 * GB,
    transport: 'nvme',
    removable: false,
    freeSpace: 0,
    detectedOS: ['Windows 11'],
    partitions: [
      { path: '/dev/nvme0n1p1', size: 0.1 * GB, fstype: 'vfat', label: 'EFI', os: 'efi' },
      { path: '/dev/nvme0n1p2', size: 0.016 * GB, label: 'Microsoft reserved', os: 'data' },
      { path: '/dev/nvme0n1p3', size: 930.7 * GB, fstype: 'ntfs', label: 'Windows', os: 'windows', used: 412 * GB },
      { path: '/dev/nvme0n1p4', size: 0.7 * GB, fstype: 'ntfs', label: 'Recovery', os: 'data' },
    ],
    shrinkable: { partition: '/dev/nvme0n1p3', maxBytes: 930.7 * GB - 412 * GB - SAFETY_MARGIN },
  },
  {
    path: '/dev/sda',
    model: 'Crucial MX500 2TB',
    size: 1863 * GB,
    transport: 'sata',
    removable: false,
    freeSpace: 400 * GB,
    detectedOS: [],
    partitions: [{ path: '/dev/sda1', size: 1463 * GB, fstype: 'ntfs', label: 'Jeux', os: 'data', used: 900 * GB }],
  },
  {
    path: '/dev/sdb',
    model: 'Clé USB 32 Go',
    size: 28.6 * GB,
    transport: 'usb',
    removable: true,
    freeSpace: 0,
    detectedOS: [],
    isBootMedia: true,
    partitions: [{ path: '/dev/sdb1', size: 1.4 * GB, fstype: 'iso9660', label: 'HEARTH_LIVE' }],
  },
];

interface LsblkDev {
  name: string;
  path: string;
  size: number;
  type: string;
  fstype?: string | null;
  label?: string | null;
  partlabel?: string | null;
  parttype?: string | null;
  model?: string | null;
  tran?: string | null;
  rm?: boolean;
  mountpoints?: (string | null)[];
  children?: LsblkDev[];
}

export async function listDisks(): Promise<Disk[]> {
  if (MOCK) return mockDisks;
  const out = await run('lsblk', ['-J', '-b', '-o', 'NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,PARTTYPE,MODEL,TRAN,RM,MOUNTPOINTS']);
  const devs = (JSON.parse(out).blockdevices as LsblkDev[]).filter((d) => d.type === 'disk' && !/^(loop|zram|sr)/.test(d.name));
  const disks: Disk[] = [];
  for (const d of devs) {
    const children = d.children ?? [];
    const hasEsp = children.some((c) => c.parttype === ESP_GUID);
    const partitions: Partition[] = children.map((c) => {
      let os: Partition['os'] = 'data';
      if (c.parttype === ESP_GUID) os = 'efi';
      else if (c.fstype === 'ntfs' && c.parttype === MS_BASIC_GUID && hasEsp && c.size > 30 * GB) os = 'windows';
      else if (c.fstype === 'ext4' || c.fstype === 'btrfs' || c.fstype === 'xfs') os = 'linux';
      return { path: c.path, size: c.size, fstype: c.fstype ?? undefined, label: c.label ?? c.partlabel ?? undefined, os };
    });
    const isBootMedia = children.some((c) => c.mountpoints?.some((m) => m?.startsWith('/run/archiso')));
    const detectedOS: string[] = [];
    if (partitions.some((p) => p.os === 'windows')) detectedOS.push('Windows');
    if (partitions.some((p) => p.os === 'linux')) detectedOS.push('Linux');

    const disk: Disk = {
      path: d.path,
      model: d.model?.trim() || d.name,
      size: d.size,
      transport: d.tran ?? 'inconnu',
      removable: !!d.rm,
      partitions,
      freeSpace: await largestFree(d.path).catch(() => 0),
      detectedOS,
      isBootMedia,
    };
    const win = partitions.filter((p) => p.os === 'windows').sort((a, b) => b.size - a.size)[0];
    if (win) {
      const min = await ntfsMinSize(win.path).catch(() => null);
      if (min) disk.shrinkable = { partition: win.path, maxBytes: Math.max(0, win.size - min - SAFETY_MARGIN) };
    }
    disks.push(disk);
  }
  return disks;
}

async function largestFree(disk: string): Promise<number> {
  const out = await runRoot('parted', ['-m', '-s', disk, 'unit', 'B', 'print', 'free']);
  let max = 0;
  for (const line of out.split('\n')) {
    if (!line.includes(':free;')) continue;
    const size = Number(line.split(':')[3]?.replace('B', ''));
    if (size > max) max = size;
  }
  return max;
}

async function ntfsMinSize(part: string): Promise<number | null> {
  const out = await runRoot('ntfsresize', ['--info', '--force', '--no-action', part]);
  const m = out.match(/You might resize at (\d+) bytes/);
  return m ? Number(m[1]) : null;
}
