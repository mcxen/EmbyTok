
import { ServerConfig, ServerType } from '../types';
import { MediaClient } from './MediaClient';
import { EmbyClient } from './EmbyClient';
import { PlexClient } from './PlexClient';
import { LocalClient } from './LocalClient';

interface CreateClientOptions {
    localFiles?: File[];
}

export class ClientFactory {
    static create(config: ServerConfig, options: CreateClientOptions = {}): MediaClient {
        if (config.serverType === 'plex') {
            return new PlexClient(config);
        }
        if (config.serverType === 'local') {
            return new LocalClient(config, options.localFiles || []);
        }
        return new EmbyClient(config);
    }

    static async authenticate(type: ServerType, url: string, username: string, password: string): Promise<ServerConfig> {
        if (type === 'local') {
            return {
                url: 'local://folder',
                username: username || 'Local User',
                token: '',
                userId: 'local-user',
                serverType: 'local',
            };
        }

        // Create a dummy config to instantiate the client for auth
        const dummyConfig: ServerConfig = { url, username: '', token: '', userId: '', serverType: type };
        const client = this.create(dummyConfig);
        return client.authenticate(username, password);
    }
}
