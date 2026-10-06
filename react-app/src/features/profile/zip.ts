/**
 * Minimal store-only (method 0, no compression) ZIP writer.
 *
 * Just enough of PKWARE APPNOTE for Obsidian-vault export: local file
 * headers + data, a central directory, and the end-of-central-directory
 * record. UTF-8 names are flagged (general-purpose bit 11), CRC-32 is the
 * standard IEEE polynomial. No ZIP64 — archives are limited to 65 535 entries
 * and 4 GiB, which `buildZip` enforces by throwing rather than emitting a
 * corrupt file.
 */

export interface ZipEntry {
  /** Path inside the archive, forward slashes, no leading slash. */
  name: string;
  data: Uint8Array;
  /** Modification time stored in the MS-DOS fields. Defaults to now. */
  modified?: Date;
}

const CRC_TABLE: Uint32Array = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

/** Standard CRC-32 (IEEE 802.3), returned as an unsigned 32-bit integer. */
export function crc32(data: Uint8Array): number {
  let crc = 0xffffffff;
  for (let i = 0; i < data.length; i++) {
    crc = CRC_TABLE[(crc ^ data[i]) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/** MS-DOS time/date words (2-second resolution, years 1980–2107). */
function dosDateTime(d: Date): { time: number; date: number } {
  const year = Math.min(2107, Math.max(1980, d.getFullYear()));
  return {
    time: (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1),
    date: ((year - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate(),
  };
}

const FLAG_UTF8 = 0x0800;
const VERSION = 20; // 2.0 — minimum needed for a plain stored entry
const MAX_U32 = 0xffffffff;

/** Build a `.zip` archive (stored, uncompressed) from the given entries. */
export function buildZip(entries: ZipEntry[]): Uint8Array {
  if (entries.length > 0xffff) {
    throw new Error('Too many files for a ZIP archive without ZIP64');
  }

  const encoder = new TextEncoder();
  const now = new Date();

  const prepared = entries.map((e) => {
    const nameBytes = encoder.encode(e.name);
    const { time, date } = dosDateTime(e.modified ?? now);
    return { nameBytes, data: e.data, crc: crc32(e.data), time, date };
  });

  let localSize = 0;
  let centralSize = 0;
  for (const p of prepared) {
    localSize += 30 + p.nameBytes.length + p.data.length;
    centralSize += 46 + p.nameBytes.length;
  }
  const total = localSize + centralSize + 22;
  if (total > MAX_U32) throw new Error('Archive too large for a ZIP without ZIP64');

  const out = new Uint8Array(total);
  const view = new DataView(out.buffer);
  let pos = 0;
  const offsets: number[] = [];

  // Local file headers + data.
  for (const p of prepared) {
    offsets.push(pos);
    view.setUint32(pos, 0x04034b50, true); // local file header signature
    view.setUint16(pos + 4, VERSION, true); // version needed
    view.setUint16(pos + 6, FLAG_UTF8, true); // general purpose flags
    view.setUint16(pos + 8, 0, true); // method: stored
    view.setUint16(pos + 10, p.time, true);
    view.setUint16(pos + 12, p.date, true);
    view.setUint32(pos + 14, p.crc, true);
    view.setUint32(pos + 18, p.data.length, true); // compressed size
    view.setUint32(pos + 22, p.data.length, true); // uncompressed size
    view.setUint16(pos + 26, p.nameBytes.length, true);
    view.setUint16(pos + 28, 0, true); // extra field length
    out.set(p.nameBytes, pos + 30);
    out.set(p.data, pos + 30 + p.nameBytes.length);
    pos += 30 + p.nameBytes.length + p.data.length;
  }

  // Central directory.
  const centralStart = pos;
  prepared.forEach((p, i) => {
    view.setUint32(pos, 0x02014b50, true); // central directory signature
    view.setUint16(pos + 4, VERSION, true); // version made by
    view.setUint16(pos + 6, VERSION, true); // version needed
    view.setUint16(pos + 8, FLAG_UTF8, true);
    view.setUint16(pos + 10, 0, true); // method: stored
    view.setUint16(pos + 12, p.time, true);
    view.setUint16(pos + 14, p.date, true);
    view.setUint32(pos + 16, p.crc, true);
    view.setUint32(pos + 20, p.data.length, true);
    view.setUint32(pos + 24, p.data.length, true);
    view.setUint16(pos + 28, p.nameBytes.length, true);
    view.setUint16(pos + 30, 0, true); // extra field length
    view.setUint16(pos + 32, 0, true); // comment length
    view.setUint16(pos + 34, 0, true); // disk number start
    view.setUint16(pos + 36, 0, true); // internal attributes
    view.setUint32(pos + 38, 0, true); // external attributes
    view.setUint32(pos + 42, offsets[i], true); // local header offset
    out.set(p.nameBytes, pos + 46);
    pos += 46 + p.nameBytes.length;
  });

  // End of central directory.
  view.setUint32(pos, 0x06054b50, true);
  view.setUint16(pos + 4, 0, true); // this disk
  view.setUint16(pos + 6, 0, true); // disk with central directory
  view.setUint16(pos + 8, prepared.length, true);
  view.setUint16(pos + 10, prepared.length, true);
  view.setUint32(pos + 12, pos - centralStart, true); // central directory size
  view.setUint32(pos + 16, centralStart, true); // central directory offset
  view.setUint16(pos + 20, 0, true); // comment length

  return out;
}
