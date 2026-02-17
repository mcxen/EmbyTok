import React, { useEffect, useMemo, useState } from 'react';
import { X, RefreshCw, Plus, CheckCircle2, FolderOpen, ArrowUpCircle, Trash2, Loader2 } from 'lucide-react';

interface FolderServiceInfo {
  id: string;
  name: string;
  mediaRoot: string;
  isActive?: boolean;
  videoCount?: number;
}

interface FolderServiceSummary {
  id: string;
  name: string;
  isActive?: boolean;
}

interface AdminConfigResponse {
  currentServiceId: string | null;
  browseRoots: string[];
  services: FolderServiceInfo[];
}

interface BrowseDirItem {
  name: string;
  path: string;
}

interface BrowseResponse {
  currentPath: string;
  parentPath: string | null;
  directories: BrowseDirItem[];
}

interface FolderServiceAdminProps {
  isOpen: boolean;
  serverUrl: string;
  onClose: () => void;
  onServicesUpdated?: (services: FolderServiceSummary[], currentServiceId: string | null) => void;
}

const normalizeServerUrl = (rawUrl: string) => {
  const trimmed = rawUrl.trim();
  if (!trimmed) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed.replace(/\/$/, '');
  }
  return `http://${trimmed}`.replace(/\/$/, '');
};

const FolderServiceAdmin: React.FC<FolderServiceAdminProps> = ({
  isOpen,
  serverUrl,
  onClose,
  onServicesUpdated,
}) => {
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [config, setConfig] = useState<AdminConfigResponse | null>(null);
  const [browseData, setBrowseData] = useState<BrowseResponse | null>(null);
  const [serviceName, setServiceName] = useState('');
  const [servicePath, setServicePath] = useState('');

  const baseUrl = useMemo(() => normalizeServerUrl(serverUrl), [serverUrl]);

  const notifyServicesUpdated = (nextConfig: AdminConfigResponse | null) => {
    if (!nextConfig || !onServicesUpdated) {
      return;
    }
    onServicesUpdated(
      nextConfig.services.map((service) => ({
        id: service.id,
        name: service.name,
        isActive: service.id === nextConfig.currentServiceId,
      })),
      nextConfig.currentServiceId
    );
  };

  const requestJson = async <T,>(path: string, init?: RequestInit): Promise<T> => {
    let response: Response;
    try {
      response = await fetch(`${baseUrl}${path}`, {
        ...init,
        headers: {
          'Content-Type': 'application/json',
          ...(init?.headers || {}),
        },
      });
    } catch {
      throw new Error(`无法连接文件服务：${baseUrl}。请确认服务端已启动并可访问。`);
    }
    if (!response.ok) {
      let message = `请求失败 (${response.status})`;
      try {
        const body = await response.json();
        if (typeof body?.error === 'string') {
          message = body.error;
        }
      } catch {
        // ignore body parse failure
      }
      throw new Error(message);
    }
    return response.json();
  };

  const loadBrowse = async (targetPath?: string) => {
    if (!baseUrl) return;
    const query = targetPath ? `?path=${encodeURIComponent(targetPath)}` : '';
    const data = await requestJson<BrowseResponse>(`/api/admin/browse${query}`);
    setBrowseData(data);
    if (!servicePath) {
      setServicePath(data.currentPath);
    }
  };

  const loadConfig = async () => {
    if (!baseUrl) return;
    setLoading(true);
    setError('');
    try {
      const data = await requestJson<AdminConfigResponse>('/api/admin/config');
      setConfig(data);
      notifyServicesUpdated(data);
      await loadBrowse();
    } catch (err: any) {
      setError(err?.message || '加载管理配置失败');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!isOpen) {
      return;
    }
    if (!baseUrl) {
      setError('请先填写文件服务地址，再打开管理页面。');
      return;
    }
    loadConfig();
  }, [isOpen, baseUrl]);

  if (!isOpen) {
    return null;
  }

  const handleCreateService = async () => {
    if (!baseUrl) {
      setError('请先填写文件服务地址');
      return;
    }
    if (!serviceName.trim() || !servicePath.trim()) {
      setError('请填写服务名称和文件夹路径');
      return;
    }

    setSaving(true);
    setError('');
    try {
      const nextConfig = await requestJson<AdminConfigResponse>('/api/admin/services', {
        method: 'POST',
        body: JSON.stringify({
          name: serviceName.trim(),
          mediaRoot: servicePath.trim(),
          setActive: true,
        }),
      });
      setConfig(nextConfig);
      notifyServicesUpdated(nextConfig);
      setServiceName('');
    } catch (err: any) {
      setError(err?.message || '创建服务失败');
    } finally {
      setSaving(false);
    }
  };

  const handleSelectActive = async (serviceId: string) => {
    setSaving(true);
    setError('');
    try {
      const nextConfig = await requestJson<AdminConfigResponse>('/api/admin/select', {
        method: 'POST',
        body: JSON.stringify({ serviceId }),
      });
      setConfig(nextConfig);
      notifyServicesUpdated(nextConfig);
    } catch (err: any) {
      setError(err?.message || '切换当前服务失败');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteService = async (serviceId: string) => {
    setSaving(true);
    setError('');
    try {
      const nextConfig = await requestJson<AdminConfigResponse>(`/api/admin/services/${encodeURIComponent(serviceId)}`, {
        method: 'DELETE',
      });
      setConfig(nextConfig);
      notifyServicesUpdated(nextConfig);
    } catch (err: any) {
      setError(err?.message || '删除服务失败');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[100] bg-black/85 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-5xl h-[90vh] bg-zinc-950 border border-zinc-800 rounded-2xl overflow-hidden flex flex-col">
        <div className="h-14 border-b border-zinc-800 px-4 flex items-center justify-between">
          <div>
            <h2 className="text-white font-bold text-lg">视频流服务管理</h2>
            <p className="text-[11px] text-zinc-500">{baseUrl || '未配置服务端地址'}</p>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={loadConfig}
              disabled={loading || saving || !baseUrl}
              className="px-3 py-2 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-sm disabled:opacity-50 flex items-center gap-2"
            >
              {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <RefreshCw className="w-4 h-4" />}
              刷新
            </button>
            <button
              type="button"
              onClick={onClose}
              className="p-2 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-300"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        <div className="flex-1 grid grid-cols-1 md:grid-cols-2 gap-0 overflow-hidden">
          <div className="border-r border-zinc-800 overflow-y-auto p-4 space-y-4">
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-3 space-y-3">
              <h3 className="text-sm font-semibold text-white">已配置服务</h3>
              {config?.services?.length ? (
                <div className="space-y-2">
                  {config.services.map((service) => (
                    <div
                      key={service.id}
                      className={`rounded-lg p-3 border ${service.isActive ? 'border-emerald-500/60 bg-emerald-500/10' : 'border-zinc-800 bg-zinc-900/60'}`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-white truncate">{service.name}</p>
                          <p className="text-[11px] text-zinc-500 truncate">{service.mediaRoot}</p>
                          {typeof service.videoCount === 'number' && (
                            <p className="text-[10px] text-zinc-600 mt-1">视频数: {service.videoCount}</p>
                          )}
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          <button
                            type="button"
                            disabled={saving || service.isActive}
                            onClick={() => handleSelectActive(service.id)}
                            className={`px-2 py-1 text-xs rounded-md ${service.isActive ? 'bg-emerald-600 text-white' : 'bg-zinc-800 hover:bg-zinc-700 text-zinc-200'} disabled:opacity-60`}
                          >
                            {service.isActive ? '当前' : '设为当前'}
                          </button>
                          <button
                            type="button"
                            disabled={saving}
                            onClick={() => handleDeleteService(service.id)}
                            className="p-1.5 rounded-md bg-zinc-800 hover:bg-zinc-700 text-zinc-300 disabled:opacity-50"
                            title="删除"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-zinc-500">还没有配置服务，请先新增一个。</p>
              )}
            </div>

            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-3 space-y-3">
              <h3 className="text-sm font-semibold text-white">新增服务</h3>
              <div className="space-y-2">
                <label className="text-xs text-zinc-500">服务名称</label>
                <input
                  value={serviceName}
                  onChange={(e) => setServiceName(e.target.value)}
                  placeholder="例如：家庭电影库"
                  className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-cyan-500"
                />
              </div>
              <div className="space-y-2">
                <label className="text-xs text-zinc-500">文件夹路径</label>
                <input
                  value={servicePath}
                  onChange={(e) => setServicePath(e.target.value)}
                  placeholder="/Volumes/Media/Movies"
                  className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-cyan-500"
                />
              </div>
              <button
                type="button"
                disabled={saving || loading}
                onClick={handleCreateService}
                className="w-full bg-cyan-600 hover:bg-cyan-700 disabled:opacity-50 text-white rounded-lg py-2.5 text-sm font-semibold flex items-center justify-center gap-2"
              >
                {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
                保存并设为当前
              </button>
            </div>
          </div>

          <div className="overflow-y-auto p-4 space-y-4">
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 p-3 space-y-3">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-semibold text-white">服务端文件夹浏览</h3>
                {browseData?.parentPath && (
                  <button
                    type="button"
                    disabled={loading || saving}
                    onClick={() => loadBrowse(browseData.parentPath || undefined)}
                    className="px-2 py-1 text-xs rounded-md bg-zinc-800 hover:bg-zinc-700 text-zinc-200 flex items-center gap-1"
                  >
                    <ArrowUpCircle className="w-3.5 h-3.5" />
                    上一级
                  </button>
                )}
              </div>

              <div className="p-2 rounded-md bg-zinc-900 border border-zinc-800 text-[11px] text-zinc-400 break-all">
                {browseData?.currentPath || '未加载'}
              </div>

              <div className="max-h-[46vh] overflow-y-auto border border-zinc-800 rounded-lg divide-y divide-zinc-800">
                {browseData?.directories?.length ? (
                  browseData.directories.map((dir) => (
                    <button
                      key={dir.path}
                      type="button"
                      onClick={() => {
                        setServicePath(dir.path);
                        loadBrowse(dir.path);
                      }}
                      className="w-full px-3 py-2 text-left text-sm text-zinc-200 hover:bg-zinc-800/80 flex items-center gap-2"
                    >
                      <FolderOpen className="w-4 h-4 text-cyan-400 shrink-0" />
                      <span className="truncate">{dir.name}</span>
                    </button>
                  ))
                ) : (
                  <div className="px-3 py-4 text-sm text-zinc-500">当前目录没有可浏览的子目录</div>
                )}
              </div>

              <div className="text-[11px] text-zinc-500 flex items-center gap-2">
                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
                点击目录会自动把路径填入“新增服务”的文件夹路径输入框。
              </div>
            </div>
          </div>
        </div>

        {error && (
          <div className="border-t border-zinc-800 px-4 py-2 text-sm text-red-300 bg-red-500/10">
            {error}
          </div>
        )}
      </div>
    </div>
  );
};

export default FolderServiceAdmin;
