
import React, { useEffect, useRef, useState } from 'react';
import { ServerConfig, ServerType } from '../types';
import { ClientFactory } from '../services/clientFactory';
import { Server, User, Key, Loader2, Info, FolderOpen } from 'lucide-react';
import {
  clearStartupDirectoryHandle,
  getStartupDirectoryHandle,
  isStartupFolderSupported,
  loadVideoFilesFromDirectory,
  pickDirectoryHandle,
  queryDirectoryPermission,
  requestDirectoryPermission,
  saveStartupDirectoryHandle,
} from '../services/localFolderService';

interface LoginProps {
  onLogin: (config: ServerConfig, localFiles?: File[]) => void;
}

const LOCAL_VIDEO_EXTENSIONS = new Set([
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

const isVideoFile = (file: File) => {
  if (file.type.startsWith('video/')) {
    return true;
  }
  const lastDot = file.name.lastIndexOf('.');
  if (lastDot < 0) {
    return false;
  }
  const ext = file.name.slice(lastDot + 1).toLowerCase();
  return LOCAL_VIDEO_EXTENSIONS.has(ext);
};

const Login: React.FC<LoginProps> = ({ onLogin }) => {
  const [serverType, setServerType] = useState<ServerType>('emby');
  const [serverUrl, setServerUrl] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [localLoading, setLocalLoading] = useState(false);
  const [error, setError] = useState('');
  const [hasStartupFolder, setHasStartupFolder] = useState(false);
  const folderInputRef = useRef<HTMLInputElement>(null);
  const isLocalMode = serverType === 'local';
  const supportsStartupFolder = isStartupFolderSupported();

  const getLocalConfig = (): ServerConfig => ({
    url: 'local://folder',
    username: 'Local Folder',
    token: '',
    userId: 'local-user',
    serverType: 'local',
  });

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isLocalMode) {
      return;
    }

    setLoading(true);
    setError('');

    // Basic validation
    let formattedUrl = serverUrl.trim();
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
        formattedUrl = `http://${formattedUrl}`;
    }

    try {
      const config = await ClientFactory.authenticate(serverType, formattedUrl, username, password);
      onLogin(config);
    } catch (err: any) {
      console.error(err);
      setError(serverType === 'plex' 
        ? 'Plex连接失败。请尝试使用X-Plex-Token作为密码。'
        : '连接失败。请检查地址、账号密码，并确保服务端允许跨域访问（CORS）。');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let cancelled = false;
    if (!supportsStartupFolder) {
      return;
    }

    getStartupDirectoryHandle()
      .then((handle) => {
        if (!cancelled) {
          setHasStartupFolder(!!handle);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setHasStartupFolder(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [supportsStartupFolder]);

  const loadFromDirectoryHandle = async (handle: any, persistAsStartup: boolean) => {
    setError('');
    setLocalLoading(true);
    try {
      let permission = await queryDirectoryPermission(handle);
      if (permission !== 'granted') {
        permission = await requestDirectoryPermission(handle);
      }
      if (permission !== 'granted') {
        setError('未授予目录读取权限，无法加载本地视频。');
        return;
      }

      const files = await loadVideoFilesFromDirectory(handle);
      if (files.length === 0) {
        setError('选择的文件夹中没有可用视频文件。');
        return;
      }

      if (persistAsStartup) {
        await saveStartupDirectoryHandle(handle);
        setHasStartupFolder(true);
      }

      onLogin(getLocalConfig(), files);
    } catch (err) {
      console.error(err);
      setError('读取本地目录失败，请重试。');
    } finally {
      setLocalLoading(false);
    }
  };

  const handleConfigureStartupFolder = async () => {
    try {
      const handle = await pickDirectoryHandle();
      if (!handle) {
        return;
      }
      await loadFromDirectoryHandle(handle, true);
    } catch (err) {
      console.error(err);
      setError('打开目录选择器失败，请确认浏览器支持该功能。');
    }
  };

  const handleLoadStartupFolder = async () => {
    try {
      const handle = await getStartupDirectoryHandle();
      if (!handle) {
        setError('未找到已配置的启动目录。');
        setHasStartupFolder(false);
        return;
      }
      await loadFromDirectoryHandle(handle, false);
    } catch (err) {
      console.error(err);
      setError('读取启动目录失败。');
    }
  };

  const handleClearStartupFolder = async () => {
    try {
      await clearStartupDirectoryHandle();
      setHasStartupFolder(false);
      setError('');
    } catch (err) {
      console.error(err);
      setError('清除启动目录配置失败。');
    }
  };

  const handlePickLocalFolder = (e: React.ChangeEvent<HTMLInputElement>) => {
    setError('');
    setLocalLoading(true);
    const files = Array.from(e.target.files || []);
    const videoFiles = files.filter(isVideoFile);

    if (videoFiles.length === 0) {
      setError('选择的文件夹中没有可用视频文件。');
      setLocalLoading(false);
      return;
    }

    onLogin(getLocalConfig(), videoFiles);
    setLocalLoading(false);
    e.target.value = '';
  };

  return (
    <div className="min-h-screen bg-black flex flex-col items-center justify-center p-6 text-white">
      <div className="w-full max-w-sm space-y-8">
        <div className="text-center">
            <h1 className="text-4xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-indigo-500 to-purple-600 mb-2">
            EmbyTok
            </h1>
            <p className="text-zinc-400">竖屏媒体中心客户端</p>
        </div>

        <form onSubmit={handleLogin} className="space-y-4 bg-zinc-900/50 p-6 rounded-2xl border border-zinc-800">
          
          {/* Server Type Selector */}
          <div className="flex bg-zinc-800 rounded-lg p-1 mb-4 gap-1">
              <button 
                type="button"
                onClick={() => setServerType('emby')}
                className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-md text-sm font-bold transition-all focus:ring-2 focus:ring-indigo-500 outline-none ${serverType === 'emby' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
              >
                  Emby / Jellyfin
              </button>
              <button 
                type="button"
                onClick={() => setServerType('plex')}
                className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-md text-sm font-bold transition-all focus:ring-2 focus:ring-indigo-500 outline-none ${serverType === 'plex' ? 'bg-yellow-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
              >
                  Plex
              </button>
              <button
                type="button"
                onClick={() => setServerType('local')}
                className={`flex-1 flex items-center justify-center gap-2 py-2 rounded-md text-sm font-bold transition-all focus:ring-2 focus:ring-indigo-500 outline-none ${serverType === 'local' ? 'bg-emerald-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
              >
                  本地
              </button>
          </div>

          {!isLocalMode ? (
            <>
              <div className="space-y-2">
                <label className="text-xs font-medium text-zinc-400 uppercase">服务器地址</label>
                <div className="relative">
                    <Server className="absolute left-3 top-3 w-5 h-5 text-zinc-500" />
                    <input
                    type="text"
                    value={serverUrl}
                    onChange={(e) => setServerUrl(e.target.value)}
                    placeholder={serverType === 'plex' ? 'http://192.168.1.10:32400' : 'http://192.168.1.100:8096'}
                    className="w-full bg-zinc-800 border-none rounded-xl py-3 pl-10 text-white placeholder-zinc-600 focus:ring-2 focus:ring-indigo-500 outline-none"
                    required
                    />
                </div>
              </div>

              <div className="space-y-2">
                <label className="text-xs font-medium text-zinc-400 uppercase">用户名</label>
                <div className="relative">
                    <User className="absolute left-3 top-3 w-5 h-5 text-zinc-500" />
                    <input
                    type="text"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder={serverType === 'plex' ? '可选 (默认 User)' : 'User'}
                    className="w-full bg-zinc-800 border-none rounded-xl py-3 pl-10 text-white placeholder-zinc-600 focus:ring-2 focus:ring-indigo-500 outline-none"
                    required={serverType === 'emby'}
                    />
                </div>
              </div>

              <div className="space-y-2">
                <label className="text-xs font-medium text-zinc-400 uppercase">{serverType === 'plex' ? 'X-Plex-Token / 密码' : '密码'}</label>
                 <div className="relative">
                    <Key className="absolute left-3 top-3 w-5 h-5 text-zinc-500" />
                    <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder={serverType === 'plex' ? '必填' : '可选'}
                    className="w-full bg-zinc-800 border-none rounded-xl py-3 pl-10 text-white placeholder-zinc-600 focus:ring-2 focus:ring-indigo-500 outline-none"
                    />
                </div>
              </div>
            </>
          ) : (
            <div className="space-y-2">
              <label className="text-xs font-medium text-zinc-400 uppercase">本地视频文件夹</label>
              {supportsStartupFolder && (
                <>
                  <button
                    type="button"
                    onClick={handleConfigureStartupFolder}
                    disabled={localLoading}
                    className="w-full bg-emerald-600 hover:bg-emerald-700 disabled:opacity-60 disabled:cursor-not-allowed text-white font-bold py-3.5 rounded-xl transition-all flex items-center justify-center gap-2 focus:ring-2 focus:ring-offset-2 focus:ring-offset-black focus:ring-white outline-none"
                  >
                    {localLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : <FolderOpen className="w-5 h-5" />}
                    选择并设为启动目录
                  </button>

                  {hasStartupFolder && (
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={handleLoadStartupFolder}
                        disabled={localLoading}
                        className="flex-1 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-60 disabled:cursor-not-allowed text-white font-semibold py-2.5 rounded-lg transition-all text-sm"
                      >
                        使用已配置启动目录
                      </button>
                      <button
                        type="button"
                        onClick={handleClearStartupFolder}
                        disabled={localLoading}
                        className="px-3 py-2.5 text-xs rounded-lg border border-zinc-700 text-zinc-300 hover:text-white hover:border-zinc-500 transition-colors disabled:opacity-60"
                      >
                        清除
                      </button>
                    </div>
                  )}
                </>
              )}

              <input
                ref={folderInputRef}
                type="file"
                multiple
                accept="video/*"
                onChange={handlePickLocalFolder}
                className="hidden"
                {...({ webkitdirectory: '', directory: '' } as any)}
              />
              <button
                type="button"
                onClick={() => folderInputRef.current?.click()}
                disabled={localLoading}
                className="w-full bg-zinc-800 hover:bg-zinc-700 disabled:opacity-60 disabled:cursor-not-allowed text-white font-bold py-3.5 rounded-xl transition-all flex items-center justify-center gap-2 focus:ring-2 focus:ring-offset-2 focus:ring-offset-black focus:ring-white outline-none"
              >
                {localLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : <FolderOpen className="w-5 h-5" />}
                仅本次加载文件夹
              </button>
              <p className="text-[11px] text-zinc-500 leading-relaxed">
                {supportsStartupFolder
                  ? '支持配置启动目录：下次打开网页会自动加载（已授权时）。'
                  : '会读取你选择目录及其子目录中的全部视频文件（浏览器需支持目录上传）。'}
              </p>
            </div>
          )}

          {error && (
            <div className="p-3 bg-red-500/20 border border-red-500/50 rounded-lg text-red-200 text-sm flex gap-2">
                <Info className="w-4 h-4 mt-0.5 shrink-0" />
                <span>{error}</span>
            </div>
          )}

          {!isLocalMode && (
            <button
              type="submit"
              disabled={loading}
              className={`w-full text-white font-bold py-3.5 rounded-xl transition-all flex items-center justify-center gap-2 focus:ring-2 focus:ring-offset-2 focus:ring-offset-black focus:ring-white outline-none ${serverType === 'plex' ? 'bg-yellow-600 hover:bg-yellow-700' : 'bg-indigo-600 hover:bg-indigo-700'}`}
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : '连接'}
            </button>
          )}
        </form>
        
        <div className="text-center text-xs text-zinc-600 px-4">
            <p>EmbyTok 是非官方客户端。支持 Emby、Jellyfin、Plex 和本地文件夹模式。</p>
        </div>
      </div>
    </div>
  );
};

export default Login;
