const DB_NAME = 'embytok-local-folder-db';
const STORE_NAME = 'folder-handles';
const STARTUP_HANDLE_KEY = 'startup-folder';

const VIDEO_EXTENSIONS = new Set([
  'mp4',
  'mkv',
  'avi',
  'mov',
  'webm',
  'm4v',
  'flv',
  'wmv',
  'ts',
  'm2ts',
  '3gp',
]);

type DirectoryPermission = 'granted' | 'prompt' | 'denied';
type DirectoryHandleLike = any;

const getExtension = (fileName: string): string => {
  const index = fileName.lastIndexOf('.');
  if (index < 0) {
    return '';
  }
  return fileName.slice(index + 1).toLowerCase();
};

const isVideoFile = (file: File): boolean => {
  if (file.type.startsWith('video/')) {
    return true;
  }
  return VIDEO_EXTENSIONS.has(getExtension(file.name));
};

const openDb = (): Promise<IDBDatabase> =>
  new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('Failed to open IndexedDB'));
  });

const runWrite = async (key: string, value: unknown): Promise<void> => {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put(value, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error('IndexedDB write failed'));
  });
  db.close();
};

const runDelete = async (key: string): Promise<void> => {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).delete(key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error('IndexedDB delete failed'));
  });
  db.close();
};

const runRead = async <T>(key: string): Promise<T | null> => {
  const db = await openDb();
  const value = await new Promise<T | null>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readonly');
    const request = tx.objectStore(STORE_NAME).get(key);
    request.onsuccess = () => resolve((request.result as T) || null);
    request.onerror = () => reject(request.error || new Error('IndexedDB read failed'));
  });
  db.close();
  return value;
};

const setRelativePath = (file: File, relativePath: string): File => {
  try {
    Object.defineProperty(file, 'relativePath', {
      value: relativePath,
      configurable: true,
      enumerable: false,
    });
  } catch {
    (file as any).relativePath = relativePath;
  }
  return file;
};

const walkDirectory = async (
  dirHandle: DirectoryHandleLike,
  currentPath: string,
  output: File[]
): Promise<void> => {
  if (!dirHandle || typeof dirHandle.entries !== 'function') {
    return;
  }

  for await (const [name, entry] of dirHandle.entries() as AsyncIterable<[string, any]>) {
    const relativePath = currentPath ? `${currentPath}/${name}` : name;
    if (entry.kind === 'directory') {
      await walkDirectory(entry, relativePath, output);
      continue;
    }
    if (entry.kind !== 'file' || typeof entry.getFile !== 'function') {
      continue;
    }

    const file = await entry.getFile();
    if (!isVideoFile(file)) {
      continue;
    }

    output.push(setRelativePath(file, relativePath));
  }
};

const callPermission = async (
  handle: DirectoryHandleLike,
  method: 'queryPermission' | 'requestPermission'
): Promise<DirectoryPermission> => {
  if (!handle || typeof handle[method] !== 'function') {
    return 'denied';
  }

  try {
    const result = await handle[method]({ mode: 'read' });
    if (result === 'granted' || result === 'prompt' || result === 'denied') {
      return result;
    }
    return 'denied';
  } catch {
    return 'denied';
  }
};

export const isStartupFolderSupported = (): boolean => {
  return typeof window !== 'undefined' && typeof (window as any).showDirectoryPicker === 'function';
};

export const pickDirectoryHandle = async (): Promise<DirectoryHandleLike | null> => {
  if (!isStartupFolderSupported()) {
    return null;
  }
  try {
    return await (window as any).showDirectoryPicker({ mode: 'read' });
  } catch (error: any) {
    if (error?.name === 'AbortError') {
      return null;
    }
    throw error;
  }
};

export const queryDirectoryPermission = async (
  handle: DirectoryHandleLike
): Promise<DirectoryPermission> => {
  return callPermission(handle, 'queryPermission');
};

export const requestDirectoryPermission = async (
  handle: DirectoryHandleLike
): Promise<DirectoryPermission> => {
  return callPermission(handle, 'requestPermission');
};

export const saveStartupDirectoryHandle = async (handle: DirectoryHandleLike): Promise<void> => {
  await runWrite(STARTUP_HANDLE_KEY, handle);
};

export const getStartupDirectoryHandle = async (): Promise<DirectoryHandleLike | null> => {
  return runRead<DirectoryHandleLike>(STARTUP_HANDLE_KEY);
};

export const clearStartupDirectoryHandle = async (): Promise<void> => {
  await runDelete(STARTUP_HANDLE_KEY);
};

export const loadVideoFilesFromDirectory = async (handle: DirectoryHandleLike): Promise<File[]> => {
  const files: File[] = [];
  await walkDirectory(handle, '', files);
  return files.sort((a, b) => b.lastModified - a.lastModified);
};
