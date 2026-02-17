import { MediaClient } from './MediaClient';
import { EmbyItem, EmbyLibrary, FeedType, OrientationMode, ServerConfig, VideoResponse } from '../types';

interface FolderLibrariesResponse {
    items?: EmbyLibrary[];
}

interface FolderServiceItem {
    id: string;
    name: string;
    isActive?: boolean;
}

interface FolderServicesResponse {
    items?: FolderServiceItem[];
    currentServiceId?: string;
}

interface FolderVideosResponse {
    items?: EmbyItem[];
    totalCount?: number;
    nextStartIndex?: number;
}

const FAVORITES_STORAGE_PREFIX = 'embytokFolderFavorites';

export class FolderServerClient extends MediaClient {
    private getCleanUrl() {
        return this.config.url.replace(/\/$/, '');
    }

    private getFavoritesStorageKey() {
        return `${FAVORITES_STORAGE_PREFIX}:${this.getCleanUrl()}:${this.getServiceId()}`;
    }

    private getServiceId() {
        return this.config.token || '';
    }

    private appendServiceId(pathname: string): string {
        const serviceId = this.getServiceId();
        if (!serviceId) {
            return pathname;
        }
        const separator = pathname.includes('?') ? '&' : '?';
        return `${pathname}${separator}serviceId=${encodeURIComponent(serviceId)}`;
    }

    private async fetchJson<T>(path: string): Promise<T> {
        const response = await fetch(`${this.getCleanUrl()}${path}`, {
            headers: {
                'Accept': 'application/json',
            },
        });

        if (!response.ok) {
            throw new Error(`Folder server request failed: ${response.status}`);
        }
        return response.json();
    }

    async authenticate(username: string, password: string): Promise<ServerConfig> {
        const ping = await this.fetchJson<{ ok: boolean }>('/api/folder/ping');
        if (!ping?.ok) {
            throw new Error('Folder server unavailable');
        }

        const services = await this.fetchJson<FolderServicesResponse>('/api/folder/services');
        const list = services.items || [];
        const requestedId = String(password || '').trim();

        let selected = list.find((item) => item.id === requestedId || item.name === requestedId);
        if (!selected && services.currentServiceId) {
            selected = list.find((item) => item.id === services.currentServiceId);
        }
        if (!selected) {
            selected = list[0];
        }
        if (!selected) {
            throw new Error('No folder stream service configured on server');
        }

        return {
            url: this.config.url,
            username: username || 'Folder User',
            userId: selected.id,
            token: selected.id,
            serverType: 'folder',
        };
    }

    async getLibraries(): Promise<EmbyLibrary[]> {
        const data = await this.fetchJson<FolderLibrariesResponse>(this.appendServiceId('/api/folder/libraries'));
        return data.items || [];
    }

    private async fetchVideosPage(
        parentId: string | undefined,
        feedType: FeedType,
        skip: number,
        limit: number,
        orientationMode: OrientationMode
    ): Promise<VideoResponse> {
        const params = new URLSearchParams({
            feedType,
            skip: String(skip),
            limit: String(limit),
            orientationMode,
        });
        if (parentId) {
            params.set('libraryId', parentId);
        }

        const data = await this.fetchJson<FolderVideosResponse>(this.appendServiceId(`/api/folder/videos?${params.toString()}`));
        const items = data.items || [];
        const totalCount = typeof data.totalCount === 'number' ? data.totalCount : items.length;
        const nextStartIndex = typeof data.nextStartIndex === 'number'
            ? data.nextStartIndex
            : Math.min(skip + items.length, totalCount);

        return {
            items,
            totalCount,
            nextStartIndex,
        };
    }

    async getVideos(
        parentId: string | undefined,
        _libraryName: string,
        feedType: FeedType,
        skip: number,
        limit: number,
        orientationMode: OrientationMode
    ): Promise<VideoResponse> {
        if (feedType !== 'favorites') {
            return this.fetchVideosPage(parentId, feedType, skip, limit, orientationMode);
        }

        const favorites = await this.getFavorites('');
        if (favorites.size === 0) {
            return {
                items: [],
                totalCount: 0,
                nextStartIndex: 0,
            };
        }

        const full = await this.fetchVideosPage(parentId, 'latest', 0, 5000, orientationMode);
        const filtered = full.items.filter(item => favorites.has(item.Id));
        const paged = filtered.slice(skip, skip + limit);

        return {
            items: paged,
            totalCount: filtered.length,
            nextStartIndex: Math.min(skip + paged.length, filtered.length),
        };
    }

    getVideoUrl(item: EmbyItem): string {
        return `${this.getCleanUrl()}${this.appendServiceId(`/api/folder/stream/${encodeURIComponent(item.Id)}`)}`;
    }

    getImageUrl(_itemId: string, _tag?: string, _type?: 'Primary' | 'Backdrop'): string {
        return '';
    }

    private readFavorites(): Set<string> {
        try {
            const raw = localStorage.getItem(this.getFavoritesStorageKey());
            if (!raw) {
                return new Set();
            }
            const parsed = JSON.parse(raw);
            if (!Array.isArray(parsed)) {
                return new Set();
            }
            return new Set(parsed.filter((value): value is string => typeof value === 'string'));
        } catch {
            return new Set();
        }
    }

    private writeFavorites(favorites: Set<string>) {
        localStorage.setItem(this.getFavoritesStorageKey(), JSON.stringify(Array.from(favorites)));
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
}
