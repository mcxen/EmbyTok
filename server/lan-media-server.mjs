import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import os from 'node:os';

const VIDEO_EXTENSIONS = new Set([
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.webm',
  '.m4v',
  '.flv',
  '.wmv',
  '.ts',
  '.m2ts',
  '.3gp',
]);
const TS_VIDEO_MIN_BYTES = 5 * 1024 * 1024;

const MIME_BY_EXT = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.mp4': 'video/mp4',
  '.mkv': 'video/x-matroska',
  '.mov': 'video/quicktime',
  '.avi': 'video/x-msvideo',
  '.webm': 'video/webm',
  '.m4v': 'video/x-m4v',
  '.flv': 'video/x-flv',
  '.wmv': 'video/x-ms-wmv',
  '.ts': 'video/mp2t',
  '.m2ts': 'video/mp2t',
  '.3gp': 'video/3gpp',
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..');

const parseArgs = () => {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const next = args[i + 1];
    if (!next || next.startsWith('--')) {
      out[key] = 'true';
      continue;
    }
    out[key] = next;
    i += 1;
  }
  return out;
};

const args = parseArgs();
const HOST = process.env.HOST || args.host || '0.0.0.0';
const PORT = Number(process.env.PORT || args.port || 5176);
const initialMediaRootInput = process.env.MEDIA_ROOT || args.media;
const INITIAL_MEDIA_ROOT = initialMediaRootInput ? path.resolve(initialMediaRootInput) : null;
const WEB_ROOT = path.resolve(process.env.WEB_ROOT || args.web || path.join(projectRoot, 'dist'));
const RESCAN_MS = Number(process.env.RESCAN_MS || args.rescan || 15000);
const SERVE_WEB = (process.env.SERVE_WEB || args.serveWeb || 'true') !== 'false';
const CONFIG_PATH = path.resolve(process.env.LAN_CONFIG_FILE || args.config || path.join(projectRoot, 'lan-media-config.json'));

const unique = (items) => Array.from(new Set(items.filter(Boolean)));

const discoverWindowsRoots = () => {
  const roots = [];
  for (let i = 65; i <= 90; i += 1) {
    const letter = String.fromCharCode(i);
    const drive = `${letter}:\\`;
    if (fs.existsSync(drive)) {
      roots.push(path.resolve(drive));
    }
  }
  return roots;
};

const buildBrowseRoots = () => {
  const configured = process.env.BROWSE_ROOTS || args.browseRoots;
  if (configured) {
    const roots = configured
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => path.resolve(item));
    return unique(roots);
  }

  if (INITIAL_MEDIA_ROOT) {
    return unique([path.parse(INITIAL_MEDIA_ROOT).root, INITIAL_MEDIA_ROOT]);
  }

  if (process.platform === 'win32') {
    const roots = discoverWindowsRoots();
    return roots.length > 0 ? roots : [path.resolve('C:\\')];
  }

  return ['/'];
};

const BROWSE_ROOTS = buildBrowseRoots();

const isInsideOrEqual = (basePath, targetPath) => {
  const rel = path.relative(basePath, targetPath);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
};

const canBrowsePath = (targetPath) => {
  return BROWSE_ROOTS.some((root) => isInsideOrEqual(path.resolve(root), path.resolve(targetPath)));
};

const getExt = (fileName) => path.extname(fileName).toLowerCase();

const json = (res, statusCode, body) => {
  const text = JSON.stringify(body);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(text);
};

const parseBody = async (req) => {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString('utf-8').trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error('Invalid JSON body');
  }
};

const shuffle = (input) => {
  const arr = [...input];
  for (let i = arr.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
};

const makeServiceId = (name, mediaRoot) => {
  return createHash('sha1')
    .update(`${name}:${mediaRoot}:${Date.now()}:${Math.random()}`)
    .digest('hex')
    .slice(0, 16);
};

const buildVideoId = (serviceId, relativePath) => {
  return createHash('sha1').update(`${serviceId}:${relativePath}`).digest('hex');
};

const createEmptyScanState = () => ({
  items: [],
  itemMap: new Map(),
  libraries: [],
  lastScanAt: 0,
  scanPromise: null,
});

const state = {
  config: {
    currentServiceId: null,
    services: [],
  },
  scanCache: new Map(),
};

const getServiceById = (serviceId) => {
  if (!serviceId) return null;
  return state.config.services.find((service) => service.id === serviceId) || null;
};

const getScanState = (serviceId) => {
  if (!state.scanCache.has(serviceId)) {
    state.scanCache.set(serviceId, createEmptyScanState());
  }
  return state.scanCache.get(serviceId);
};

const invalidateScanState = (serviceId) => {
  state.scanCache.delete(serviceId);
};

const sanitizeName = (name) => String(name || '').trim();
const sanitizeMediaRoot = (mediaRoot) => path.resolve(String(mediaRoot || '').trim());

const readConfigFile = async () => {
  try {
    const raw = await fsp.readFile(CONFIG_PATH, 'utf-8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
};

const saveConfigFile = async () => {
  await fsp.mkdir(path.dirname(CONFIG_PATH), { recursive: true });
  await fsp.writeFile(CONFIG_PATH, JSON.stringify(state.config, null, 2), 'utf-8');
};

const ensureDefaultConfig = async () => {
  const loaded = await readConfigFile();
  const services = [];

  if (loaded && Array.isArray(loaded.services)) {
    loaded.services.forEach((item) => {
      if (!item || typeof item !== 'object') return;
      const name = sanitizeName(item.name);
      const mediaRoot = sanitizeMediaRoot(item.mediaRoot);
      const id = sanitizeName(item.id);
      if (!name || !mediaRoot || !id) return;
      services.push({
        id,
        name,
        mediaRoot,
      });
    });
  }

  if (services.length === 0 && INITIAL_MEDIA_ROOT) {
    services.push({
      id: makeServiceId('默认视频流', INITIAL_MEDIA_ROOT),
      name: '默认视频流',
      mediaRoot: INITIAL_MEDIA_ROOT,
    });
  }

  const currentServiceId = loaded?.currentServiceId && services.some((s) => s.id === loaded.currentServiceId)
    ? loaded.currentServiceId
    : (services[0]?.id || null);

  state.config = {
    currentServiceId,
    services,
  };

  await saveConfigFile();
};

const walkDir = async (service, dirPath, relativeBase, output) => {
  let entries = [];
  try {
    entries = await fsp.readdir(dirPath, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    const absPath = path.join(dirPath, entry.name);
    const relPath = relativeBase ? `${relativeBase}/${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      await walkDir(service, absPath, relPath, output);
      continue;
    }

    if (!entry.isFile()) continue;

    const ext = getExt(entry.name);
    if (!VIDEO_EXTENSIONS.has(ext)) continue;

    let stat;
    try {
      stat = await fsp.stat(absPath);
    } catch {
      continue;
    }

    if (ext === '.ts' && stat.size < TS_VIDEO_MIN_BYTES) continue;

    const topFolder = relPath.includes('/') ? relPath.split('/')[0] : '__root__';
    const libraryId = `${service.id}:${topFolder}`;
    const libraryName = topFolder === '__root__' ? '根目录' : topFolder;

    output.push({
      id: buildVideoId(service.id, relPath),
      serviceId: service.id,
      name: path.parse(entry.name).name || entry.name,
      relPath,
      absPath,
      ext,
      size: stat.size,
      mtimeMs: stat.mtimeMs,
      libraryId,
      libraryName,
    });
  }
};

const mapToEmbyItem = (record) => ({
  Id: record.id,
  Name: record.name,
  Type: 'Video',
  MediaType: 'Video',
  Overview: record.relPath,
  ProductionYear: new Date(record.mtimeMs).getFullYear(),
  MediaSources: [
    {
      Id: record.id,
      Container: record.ext.replace('.', ''),
      Path: record.relPath,
      Protocol: 'File',
    },
  ],
});

const scanService = async (serviceId) => {
  const service = getServiceById(serviceId);
  if (!service) {
    return;
  }

  const scan = getScanState(serviceId);

  let rootStat;
  try {
    rootStat = await fsp.stat(service.mediaRoot);
  } catch {
    rootStat = null;
  }

  if (!rootStat || !rootStat.isDirectory()) {
    scan.items = [];
    scan.itemMap = new Map();
    scan.libraries = [];
    scan.lastScanAt = Date.now();
    return;
  }

  const collected = [];
  await walkDir(service, service.mediaRoot, '', collected);
  collected.sort((a, b) => b.mtimeMs - a.mtimeMs);

  const libsMap = new Map();
  collected.forEach((item) => {
    if (!libsMap.has(item.libraryId)) {
      libsMap.set(item.libraryId, {
        Id: item.libraryId,
        Name: item.libraryName,
      });
    }
  });

  scan.items = collected;
  scan.itemMap = new Map(collected.map((item) => [item.id, item]));
  scan.libraries = Array.from(libsMap.values()).sort((a, b) => a.Name.localeCompare(b.Name, 'zh-CN'));
  scan.lastScanAt = Date.now();
};

const ensureScanned = async (serviceId, force = false) => {
  if (!getServiceById(serviceId)) {
    return;
  }

  const scan = getScanState(serviceId);
  const shouldReuse = !force && (Date.now() - scan.lastScanAt < RESCAN_MS);
  if (shouldReuse) {
    return;
  }

  if (scan.scanPromise) {
    await scan.scanPromise;
    return;
  }

  scan.scanPromise = scanService(serviceId).finally(() => {
    scan.scanPromise = null;
  });
  await scan.scanPromise;
};

const resolveRequestedService = (urlObj) => {
  const requestedId = urlObj.searchParams.get('serviceId') || state.config.currentServiceId;
  const service = getServiceById(requestedId);
  return { requestedId, service };
};

const streamVideo = async (record, req, res) => {
  const stat = await fsp.stat(record.absPath);
  const totalSize = stat.size;
  const contentType = MIME_BY_EXT[record.ext] || 'application/octet-stream';
  const range = req.headers.range;
  const sendBody = req.method !== 'HEAD';

  if (!range) {
    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': totalSize,
      'Accept-Ranges': 'bytes',
      'Access-Control-Allow-Origin': '*',
    });
    if (!sendBody) {
      res.end();
      return;
    }
    fs.createReadStream(record.absPath).pipe(res);
    return;
  }

  const match = /bytes=(\d*)-(\d*)/.exec(range);
  if (!match) {
    res.writeHead(416);
    res.end();
    return;
  }

  const start = match[1] ? Number(match[1]) : 0;
  const end = match[2] ? Number(match[2]) : totalSize - 1;

  if (Number.isNaN(start) || Number.isNaN(end) || start < 0 || end >= totalSize || start > end) {
    res.writeHead(416);
    res.end();
    return;
  }

  const chunkSize = end - start + 1;
  res.writeHead(206, {
    'Content-Type': contentType,
    'Content-Length': chunkSize,
    'Content-Range': `bytes ${start}-${end}/${totalSize}`,
    'Accept-Ranges': 'bytes',
    'Access-Control-Allow-Origin': '*',
  });

  if (!sendBody) {
    res.end();
    return;
  }
  fs.createReadStream(record.absPath, { start, end }).pipe(res);
};

const getAdminConfigPayload = () => {
  const services = state.config.services.map((service) => {
    const scan = getScanState(service.id);
    return {
      id: service.id,
      name: service.name,
      mediaRoot: service.mediaRoot,
      isActive: service.id === state.config.currentServiceId,
      videoCount: scan.items.length,
      lastScanAt: scan.lastScanAt,
    };
  });

  return {
    currentServiceId: state.config.currentServiceId,
    services,
    browseRoots: BROWSE_ROOTS,
    rescanMs: RESCAN_MS,
  };
};

const handleAdminApi = async (req, res, urlObj) => {
  if (urlObj.pathname === '/api/admin/config' && req.method === 'GET') {
    json(res, 200, getAdminConfigPayload());
    return true;
  }

  if (urlObj.pathname === '/api/admin/roots' && req.method === 'GET') {
    json(res, 200, { roots: BROWSE_ROOTS });
    return true;
  }

  if (urlObj.pathname === '/api/admin/browse' && req.method === 'GET') {
    const requestedPath = urlObj.searchParams.get('path');
    const currentPath = requestedPath ? path.resolve(requestedPath) : BROWSE_ROOTS[0];

    if (!currentPath || !path.isAbsolute(currentPath)) {
      json(res, 400, { error: 'Path must be absolute' });
      return true;
    }

    if (!canBrowsePath(currentPath)) {
      json(res, 403, { error: 'Path is outside allowed browse roots' });
      return true;
    }

    let entries = [];
    try {
      const dirEntries = await fsp.readdir(currentPath, { withFileTypes: true });
      entries = dirEntries
        .filter((entry) => entry.isDirectory())
        .map((entry) => ({
          name: entry.name,
          path: path.join(currentPath, entry.name),
        }))
        .sort((a, b) => a.name.localeCompare(b.name, 'zh-CN'));
    } catch {
      json(res, 404, { error: 'Directory not accessible' });
      return true;
    }

    const parentRaw = path.dirname(currentPath);
    const parentPath = parentRaw !== currentPath && canBrowsePath(parentRaw) ? parentRaw : null;

    json(res, 200, {
      currentPath,
      parentPath,
      directories: entries,
    });
    return true;
  }

  if (urlObj.pathname === '/api/admin/services' && req.method === 'POST') {
    let body;
    try {
      body = await parseBody(req);
    } catch (error) {
      json(res, 400, { error: error.message });
      return true;
    }

    const name = sanitizeName(body.name);
    const mediaRoot = sanitizeMediaRoot(body.mediaRoot);
    const id = sanitizeName(body.id);
    const setActive = Boolean(body.setActive);

    if (!name) {
      json(res, 400, { error: 'Service name is required' });
      return true;
    }

    if (!mediaRoot || !path.isAbsolute(mediaRoot)) {
      json(res, 400, { error: 'mediaRoot must be an absolute path' });
      return true;
    }

    if (!canBrowsePath(mediaRoot)) {
      json(res, 403, { error: 'mediaRoot is outside allowed browse roots' });
      return true;
    }

    let rootStat;
    try {
      rootStat = await fsp.stat(mediaRoot);
    } catch {
      rootStat = null;
    }

    if (!rootStat || !rootStat.isDirectory()) {
      json(res, 400, { error: 'mediaRoot is not a directory or cannot be read' });
      return true;
    }

    if (id) {
      const index = state.config.services.findIndex((service) => service.id === id);
      if (index < 0) {
        json(res, 404, { error: 'Service not found' });
        return true;
      }
      state.config.services[index] = {
        ...state.config.services[index],
        name,
        mediaRoot,
      };
      invalidateScanState(id);
    } else {
      const nextId = makeServiceId(name, mediaRoot);
      state.config.services.push({
        id: nextId,
        name,
        mediaRoot,
      });
      if (!state.config.currentServiceId || setActive) {
        state.config.currentServiceId = nextId;
      }
      invalidateScanState(nextId);
    }

    if (setActive && id) {
      state.config.currentServiceId = id;
    }

    if (!state.config.currentServiceId && state.config.services.length > 0) {
      state.config.currentServiceId = state.config.services[0].id;
    }

    await saveConfigFile();
    json(res, 200, getAdminConfigPayload());
    return true;
  }

  if (urlObj.pathname === '/api/admin/select' && req.method === 'POST') {
    let body;
    try {
      body = await parseBody(req);
    } catch (error) {
      json(res, 400, { error: error.message });
      return true;
    }

    const serviceId = sanitizeName(body.serviceId);
    if (!getServiceById(serviceId)) {
      json(res, 404, { error: 'Service not found' });
      return true;
    }

    state.config.currentServiceId = serviceId;
    await saveConfigFile();
    json(res, 200, getAdminConfigPayload());
    return true;
  }

  const deleteMatch = /^\/api\/admin\/services\/([^/]+)$/.exec(urlObj.pathname);
  if (deleteMatch && req.method === 'DELETE') {
    const serviceId = decodeURIComponent(deleteMatch[1]);
    const prevLength = state.config.services.length;
    state.config.services = state.config.services.filter((service) => service.id !== serviceId);
    if (state.config.services.length === prevLength) {
      json(res, 404, { error: 'Service not found' });
      return true;
    }

    invalidateScanState(serviceId);

    if (state.config.currentServiceId === serviceId) {
      state.config.currentServiceId = state.config.services[0]?.id || null;
    }

    await saveConfigFile();
    json(res, 200, getAdminConfigPayload());
    return true;
  }

  if (urlObj.pathname === '/api/admin/rescan' && req.method === 'POST') {
    let body = {};
    try {
      body = await parseBody(req);
    } catch {
      body = {};
    }

    const serviceId = sanitizeName(body.serviceId || state.config.currentServiceId);
    if (!getServiceById(serviceId)) {
      json(res, 404, { error: 'Service not found' });
      return true;
    }

    await ensureScanned(serviceId, true);
    json(res, 200, getAdminConfigPayload());
    return true;
  }

  return false;
};

const handleFolderApi = async (req, res, urlObj) => {
  if (urlObj.pathname === '/api/folder/ping' && req.method === 'GET') {
    json(res, 200, {
      ok: true,
      serviceCount: state.config.services.length,
      currentServiceId: state.config.currentServiceId,
    });
    return true;
  }

  if (urlObj.pathname === '/api/folder/services' && req.method === 'GET') {
    const items = state.config.services.map((service) => ({
      id: service.id,
      name: service.name,
      isActive: service.id === state.config.currentServiceId,
    }));
    json(res, 200, { items, currentServiceId: state.config.currentServiceId });
    return true;
  }

  if (urlObj.pathname === '/api/folder/rescan' && req.method === 'POST') {
    const { requestedId, service } = resolveRequestedService(urlObj);
    if (!service) {
      json(res, 404, { error: 'Service not found', requestedId });
      return true;
    }
    await ensureScanned(service.id, true);
    const scan = getScanState(service.id);
    json(res, 200, { ok: true, serviceId: service.id, videoCount: scan.items.length });
    return true;
  }

  if (urlObj.pathname === '/api/folder/libraries' && req.method === 'GET') {
    const { requestedId, service } = resolveRequestedService(urlObj);
    if (!service) {
      json(res, 404, { error: 'Service not found', requestedId });
      return true;
    }

    await ensureScanned(service.id);
    const scan = getScanState(service.id);
    json(res, 200, {
      serviceId: service.id,
      serviceName: service.name,
      items: scan.libraries,
    });
    return true;
  }

  if (urlObj.pathname === '/api/folder/videos' && req.method === 'GET') {
    const { requestedId, service } = resolveRequestedService(urlObj);
    if (!service) {
      json(res, 404, { error: 'Service not found', requestedId });
      return true;
    }

    await ensureScanned(service.id);
    const scan = getScanState(service.id);

    const libraryId = urlObj.searchParams.get('libraryId');
    const feedType = urlObj.searchParams.get('feedType') || 'latest';
    const skip = Number(urlObj.searchParams.get('skip') || 0);
    const limit = Number(urlObj.searchParams.get('limit') || 20);

    let items = scan.items;
    if (libraryId) {
      items = items.filter((item) => item.libraryId === libraryId);
    }

    let list = items;
    if (feedType === 'random') {
      list = shuffle(items);
    }

    const safeSkip = Number.isFinite(skip) && skip > 0 ? skip : 0;
    const safeLimit = Number.isFinite(limit) && limit > 0 ? limit : 20;
    const paged = list.slice(safeSkip, safeSkip + safeLimit);

    json(res, 200, {
      serviceId: service.id,
      serviceName: service.name,
      items: paged.map(mapToEmbyItem),
      totalCount: list.length,
      nextStartIndex: Math.min(safeSkip + paged.length, list.length),
    });
    return true;
  }

  if (urlObj.pathname.startsWith('/api/folder/stream/') && (req.method === 'GET' || req.method === 'HEAD')) {
    const { requestedId, service } = resolveRequestedService(urlObj);
    if (!service) {
      json(res, 404, { error: 'Service not found', requestedId });
      return true;
    }

    await ensureScanned(service.id);
    const scan = getScanState(service.id);
    const id = decodeURIComponent(urlObj.pathname.replace('/api/folder/stream/', ''));
    const record = scan.itemMap.get(id);

    if (!record) {
      json(res, 404, { error: 'Video not found' });
      return true;
    }

    await streamVideo(record, req, res);
    return true;
  }

  return false;
};

const ensureInsideWebRoot = (targetPath) => {
  const rel = path.relative(WEB_ROOT, targetPath);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
};

const serveStatic = async (reqPath, res) => {
  if (!SERVE_WEB) return false;

  let safePath = decodeURIComponent(reqPath);
  if (safePath === '/') safePath = '/index.html';

  const absolutePath = path.resolve(WEB_ROOT, `.${safePath}`);
  if (!ensureInsideWebRoot(absolutePath)) {
    return false;
  }

  const fallbackToIndex = async () => {
    const indexFile = path.join(WEB_ROOT, 'index.html');
    try {
      const content = await fsp.readFile(indexFile);
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(content);
      return true;
    } catch {
      return false;
    }
  };

  try {
    const stat = await fsp.stat(absolutePath);
    if (stat.isDirectory()) {
      return fallbackToIndex();
    }

    const content = await fsp.readFile(absolutePath);
    const ext = getExt(absolutePath);
    res.writeHead(200, {
      'Content-Type': MIME_BY_EXT[ext] || 'application/octet-stream',
      'Content-Length': content.length,
    });
    res.end(content);
    return true;
  } catch {
    if (reqPath.startsWith('/api/')) return false;
    return fallbackToIndex();
  }
};

const handleApi = async (req, res, urlObj) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.end();
    return true;
  }

  if (!urlObj.pathname.startsWith('/api/')) {
    return false;
  }

  if (urlObj.pathname.startsWith('/api/admin/')) {
    return handleAdminApi(req, res, urlObj);
  }

  if (urlObj.pathname.startsWith('/api/folder/')) {
    return handleFolderApi(req, res, urlObj);
  }

  return false;
};

const getLanUrls = () => {
  const urls = new Set();
  const nets = os.networkInterfaces();
  Object.values(nets).forEach((list) => {
    (list || []).forEach((net) => {
      if (net.family === 'IPv4' && !net.internal) {
        urls.add(`http://${net.address}:${PORT}`);
      }
    });
  });
  return Array.from(urls);
};

const bootstrap = async () => {
  await ensureDefaultConfig();

  if (state.config.currentServiceId) {
    await ensureScanned(state.config.currentServiceId, true);
  }

  const server = http.createServer(async (req, res) => {
    try {
      const urlObj = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
      const handledApi = await handleApi(req, res, urlObj);
      if (handledApi) return;

      const handledStatic = await serveStatic(urlObj.pathname, res);
      if (handledStatic) return;

      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not Found');
    } catch (error) {
      console.error(error);
      res.writeHead(500, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: 'Internal server error' }));
    }
  });

  server.listen(PORT, HOST, () => {
    const activeService = getServiceById(state.config.currentServiceId);
    const activeVideoCount = activeService ? getScanState(activeService.id).items.length : 0;

    console.log(`[lan-media-server] Config file: ${CONFIG_PATH}`);
    console.log(`[lan-media-server] Services: ${state.config.services.length}`);
    if (activeService) {
      console.log(`[lan-media-server] Active service: ${activeService.name} (${activeService.mediaRoot})`);
      console.log(`[lan-media-server] Active videos: ${activeVideoCount}`);
    } else {
      console.log('[lan-media-server] Active service: none (use /api/admin/config to add one)');
    }

    console.log(`[lan-media-server] Listening: http://${HOST}:${PORT}`);
    const lanUrls = getLanUrls();
    if (lanUrls.length > 0) {
      console.log('[lan-media-server] LAN access URLs:');
      lanUrls.forEach((url) => console.log(`  - ${url}`));
    }

    if (!SERVE_WEB) {
      console.log('[lan-media-server] Static web hosting disabled (SERVE_WEB=false).');
    } else {
      console.log(`[lan-media-server] Web root: ${WEB_ROOT}`);
    }

    console.log(`[lan-media-server] Browse roots: ${BROWSE_ROOTS.join(', ')}`);
  });
};

bootstrap().catch((error) => {
  console.error(error);
  process.exit(1);
});
