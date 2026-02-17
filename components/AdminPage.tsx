import React, { useMemo, useState } from 'react';
import FolderServiceAdmin from './FolderServiceAdmin';
import { Lock, Server, ArrowLeft } from 'lucide-react';

const ADMIN_PASSWORD = 'admin';
const ADMIN_URL_STORAGE_KEY = 'embytokAdminServerUrl';

const normalizeServerUrl = (rawUrl: string) => {
  const trimmed = rawUrl.trim();
  if (!trimmed) {
    return '';
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed.replace(/\/$/, '');
  }
  return `http://${trimmed}`.replace(/\/$/, '');
};

const getInitialServerUrl = () => {
  const fromStorage = localStorage.getItem(ADMIN_URL_STORAGE_KEY);
  if (fromStorage) {
    return fromStorage;
  }

  try {
    const raw = localStorage.getItem('embyConfig');
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed?.serverType === 'folder' && typeof parsed.url === 'string') {
        return parsed.url;
      }
    }
  } catch {
    // ignore invalid local storage payload
  }

  const { protocol, hostname, port } = window.location;
  if ((hostname === 'localhost' || hostname === '127.0.0.1') && port === '5173') {
    return `${protocol}//127.0.0.1:5176`;
  }

  return window.location.origin;
};

const AdminPage: React.FC = () => {
  const [serverUrlInput, setServerUrlInput] = useState(getInitialServerUrl);
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [isAdminOpen, setIsAdminOpen] = useState(false);
  const normalizedServerUrl = useMemo(() => normalizeServerUrl(serverUrlInput), [serverUrlInput]);

  const handleEnterAdmin = (event: React.FormEvent) => {
    event.preventDefault();
    if (!normalizedServerUrl) {
      setError('请先填写文件服务地址');
      return;
    }
    if (password !== ADMIN_PASSWORD) {
      setError('管理员密码错误');
      return;
    }
    localStorage.setItem(ADMIN_URL_STORAGE_KEY, normalizedServerUrl);
    setError('');
    setIsAdminOpen(true);
  };

  return (
    <div className="min-h-screen bg-black text-white flex items-center justify-center p-6">
      <div className="w-full max-w-md rounded-2xl border border-zinc-800 bg-zinc-900/70 p-6 space-y-5">
        <div className="space-y-1">
          <h1 className="text-2xl font-bold">管理员入口</h1>
          <p className="text-sm text-zinc-400">访问路径：/admin</p>
        </div>

        <form onSubmit={handleEnterAdmin} className="space-y-4">
          <label className="block space-y-2">
            <span className="text-xs uppercase text-zinc-500">文件服务地址</span>
            <div className="relative">
              <Server className="absolute left-3 top-3.5 w-4 h-4 text-zinc-500" />
              <input
                type="text"
                value={serverUrlInput}
                onChange={(event) => setServerUrlInput(event.target.value)}
                placeholder="http://192.168.1.50:5176"
                className="w-full rounded-xl bg-zinc-800 border border-zinc-700 py-2.5 pl-10 pr-3 outline-none focus:ring-2 focus:ring-cyan-500"
              />
            </div>
          </label>

          <label className="block space-y-2">
            <span className="text-xs uppercase text-zinc-500">管理员密码</span>
            <div className="relative">
              <Lock className="absolute left-3 top-3.5 w-4 h-4 text-zinc-500" />
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                placeholder="admin"
                className="w-full rounded-xl bg-zinc-800 border border-zinc-700 py-2.5 pl-10 pr-3 outline-none focus:ring-2 focus:ring-cyan-500"
              />
            </div>
          </label>

          {error && (
            <p className="text-sm text-red-300 bg-red-500/10 border border-red-500/40 rounded-lg px-3 py-2">
              {error}
            </p>
          )}

          <button
            type="submit"
            className="w-full rounded-xl bg-cyan-600 hover:bg-cyan-700 text-white py-2.5 font-semibold"
          >
            进入管理页面
          </button>
        </form>

        <a
          href="/"
          className="inline-flex items-center gap-2 text-sm text-zinc-400 hover:text-zinc-200 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          返回首页
        </a>
      </div>

      <FolderServiceAdmin
        isOpen={isAdminOpen}
        serverUrl={normalizedServerUrl}
        onClose={() => setIsAdminOpen(false)}
      />
    </div>
  );
};

export default AdminPage;
