import {
  EmbyItem,
  EmbyLibrary,
  FeedType,
  OrientationMode,
  ServerConfig,
  VideoResponse,
} from '../types';
import { MediaClient } from './MediaClient';

interface LocalVideoRecord {
  item: EmbyItem;
  objectUrl: string;
  lastModified: number;
}

const LOCAL_LIBRARY: EmbyLibrary = {
  Id: 'local-library',
  Name: '本地视频',
};

const LOCAL_FAVORITES_KEY = 'embytokLocalFavorites';

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

export class LocalClient extends MediaClient {
  private static activeObjectUrls: Set<string> = new Set();

  private readonly records: LocalVideoRecord[];
  private readonly videoUrlMap: Map<string, string>;

  constructor(config: ServerConfig, files: File[] = []) {
    super(config);
    const { records, urls } = this.buildRecords(files);
    this.records = records;
    this.videoUrlMap = new Map(records.map((record) => [record.item.Id, record.objectUrl]));
    this.replaceObjectUrls(urls);
  }

  async authenticate(username: string): Promise<ServerConfig> {
    return {
      url: 'local://folder',
      username: username || 'Local User',
      token: '',
      userId: 'local-user',
      serverType: 'local',
    };
  }

  async getLibraries(): Promise<EmbyLibrary[]> {
    return [LOCAL_LIBRARY];
  }

  async getVideos(
    _parentId: string | undefined,
    _libraryName: string,
    feedType: FeedType,
    skip: number,
    limit: number,
    orientationMode: OrientationMode
  ): Promise<VideoResponse> {
    const favorites = feedType === 'favorites' ? await this.getFavorites(LOCAL_LIBRARY.Name) : null;
    const visibleRecords = this.records.filter((record) => {
      if (!this.matchesOrientation(record.item, orientationMode)) {
        return false;
      }
      if (favorites && !favorites.has(record.item.Id)) {
        return false;
      }
      return true;
    });

    if (feedType === 'random') {
      const shuffled = this.shuffle(visibleRecords);
      const randomItems = shuffled.slice(0, limit).map((record) => record.item);
      return {
        items: randomItems,
        nextStartIndex: randomItems.length,
        totalCount: randomItems.length,
      };
    }

    const totalCount = visibleRecords.length;
    const pagedRecords = visibleRecords.slice(skip, skip + limit);
    return {
      items: pagedRecords.map((record) => record.item),
      nextStartIndex: Math.min(skip + pagedRecords.length, totalCount),
      totalCount,
    };
  }

  getVideoUrl(item: EmbyItem): string {
    return this.videoUrlMap.get(item.Id) || '';
  }

  getImageUrl(_itemId: string, _tag?: string, _type?: 'Primary' | 'Backdrop'): string {
    return '';
  }

  async getFavorites(_libraryName: string): Promise<Set<string>> {
    return this.readFavorites();
  }

  async toggleFavorite(itemId: string, isFavorite: boolean, _libraryName: string): Promise<void> {
    const favorites = this.readFavorites();
    if (isFavorite) {
      favorites.delete(itemId);
    } else {
      favorites.add(itemId);
    }
    this.writeFavorites(favorites);
  }

  private buildRecords(files: File[]): { records: LocalVideoRecord[]; urls: string[] } {
    const records = files
      .filter((file) => this.isVideoFile(file))
      .map((file) => {
        const relativePath = this.getRelativePath(file);
        const id = this.buildItemId(relativePath, file);
        const objectUrl = URL.createObjectURL(file);
        const ext = this.getExtension(file.name) || 'mp4';

        const item: EmbyItem = {
          Id: id,
          Name: this.getDisplayName(file.name),
          Type: 'Video',
          MediaType: 'Video',
          Overview: relativePath,
          ProductionYear: this.extractYear(file.lastModified),
          MediaSources: [
            {
              Id: id,
              Container: ext,
              Path: relativePath,
              Protocol: 'File',
            },
          ],
        };

        return {
          item,
          objectUrl,
          lastModified: file.lastModified,
        };
      })
      .sort((a, b) => b.lastModified - a.lastModified);

    return {
      records,
      urls: records.map((record) => record.objectUrl),
    };
  }

  private replaceObjectUrls(nextUrls: string[]): void {
    LocalClient.activeObjectUrls.forEach((url) => {
      URL.revokeObjectURL(url);
    });
    LocalClient.activeObjectUrls = new Set(nextUrls);
  }

  private getRelativePath(file: File): string {
    const fileWithPath = file as File & { webkitRelativePath?: string };
    return fileWithPath.webkitRelativePath || file.name;
  }

  private buildItemId(relativePath: string, file: File): string {
    return `local:${encodeURIComponent(relativePath)}:${file.size}:${file.lastModified}`;
  }

  private getDisplayName(fileName: string): string {
    const trimmed = fileName.replace(/\.[^/.]+$/, '');
    return trimmed || fileName;
  }

  private extractYear(lastModified: number): number | undefined {
    if (!lastModified) {
      return undefined;
    }
    return new Date(lastModified).getFullYear();
  }

  private getExtension(fileName: string): string {
    const index = fileName.lastIndexOf('.');
    if (index < 0) {
      return '';
    }
    return fileName.slice(index + 1).toLowerCase();
  }

  private isVideoFile(file: File): boolean {
    if (file.type.startsWith('video/')) {
      return true;
    }
    return VIDEO_EXTENSIONS.has(this.getExtension(file.name));
  }

  private matchesOrientation(item: EmbyItem, orientationMode: OrientationMode): boolean {
    if (orientationMode === 'both') {
      return true;
    }

    if (!item.Width || !item.Height) {
      return true;
    }

    const isVertical = item.Height >= item.Width;
    return orientationMode === 'vertical' ? isVertical : !isVertical;
  }

  private shuffle(records: LocalVideoRecord[]): LocalVideoRecord[] {
    const next = [...records];
    for (let i = next.length - 1; i > 0; i -= 1) {
      const randomIndex = Math.floor(Math.random() * (i + 1));
      [next[i], next[randomIndex]] = [next[randomIndex], next[i]];
    }
    return next;
  }

  private readFavorites(): Set<string> {
    try {
      const raw = localStorage.getItem(LOCAL_FAVORITES_KEY);
      if (!raw) {
        return new Set();
      }
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return new Set();
      }
      return new Set(parsed.filter((item): item is string => typeof item === 'string'));
    } catch {
      return new Set();
    }
  }

  private writeFavorites(favorites: Set<string>): void {
    localStorage.setItem(LOCAL_FAVORITES_KEY, JSON.stringify(Array.from(favorites)));
  }
}
