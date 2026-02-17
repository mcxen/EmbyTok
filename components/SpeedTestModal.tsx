import React, { useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, Gauge, Loader2, X } from 'lucide-react';
import { EmbyItem } from '../types';
import { MediaClient } from '../services/MediaClient';

interface SpeedTestModalProps {
  isOpen: boolean;
  onClose: () => void;
  client: MediaClient;
  sampleItem: EmbyItem | null;
}

type TestStatus = 'idle' | 'running' | 'done' | 'error';

const TEST_BYTES = 2 * 1024 * 1024;
const TIMEOUT_MS = 12000;

const formatBytes = (bytes: number) => {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
};

const getQualityHint = (mbps: number) => {
  if (mbps < 2) {
    return { label: '可能卡顿', detail: '建议 480p 或降低码率' };
  }
  if (mbps < 5) {
    return { label: '一般', detail: '适合 480p，720p 可能不稳' };
  }
  if (mbps < 10) {
    return { label: '流畅', detail: '适合 720p' };
  }
  return { label: '很流畅', detail: '适合 1080p 或更高' };
};

const SpeedTestModal: React.FC<SpeedTestModalProps> = ({ isOpen, onClose, client, sampleItem }) => {
  const [status, setStatus] = useState<TestStatus>('idle');
  const [error, setError] = useState('');
  const [result, setResult] = useState<{ mbps: number; bytes: number; durationMs: number } | null>(null);

  const sampleLabel = useMemo(() => {
    if (!sampleItem) return '暂无可用视频';
    return sampleItem.Name || '未命名视频';
  }, [sampleItem]);

  if (!isOpen) return null;

  const runTest = async () => {
    if (!sampleItem) {
      setStatus('error');
      setError('当前没有可用视频，请先打开一个视频后再测速。');
      return;
    }

    const url = client.getVideoUrl(sampleItem);
    if (!url) {
      setStatus('error');
      setError('无法获取视频地址，请检查服务连接。');
      return;
    }

    setStatus('running');
    setError('');
    setResult(null);

    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), TIMEOUT_MS);
    let totalBytes = 0;
    const start = performance.now();

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          Range: `bytes=0-${TEST_BYTES - 1}`,
        },
        cache: 'no-store',
        signal: controller.signal,
      });

      if (!response.ok && response.status !== 206) {
        throw new Error(`请求失败 (${response.status})`);
      }

      const reader = response.body?.getReader();
      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (value) {
            totalBytes += value.length;
            if (totalBytes >= TEST_BYTES && response.status !== 206) {
              controller.abort();
              break;
            }
          }
        }
      } else {
        const buffer = await response.arrayBuffer();
        totalBytes = buffer.byteLength;
      }

      const durationMs = performance.now() - start;
      if (totalBytes <= 0) {
        throw new Error('未获取到有效数据');
      }

      const mbps = (totalBytes * 8) / (durationMs / 1000) / 1e6;
      setResult({ mbps, bytes: totalBytes, durationMs });
      setStatus('done');
    } catch (err: any) {
      if (err?.name === 'AbortError' && totalBytes > 0) {
        const durationMs = performance.now() - start;
        const mbps = (totalBytes * 8) / (durationMs / 1000) / 1e6;
        setResult({ mbps, bytes: totalBytes, durationMs });
        setStatus('done');
      } else if (err?.name === 'AbortError') {
        setStatus('error');
        setError('测速超时，请稍后重试。');
      } else {
        setStatus('error');
        setError(err?.message || '测速失败');
      }
    } finally {
      window.clearTimeout(timeoutId);
    }
  };

  const renderResult = () => {
    if (status === 'running') {
      return (
        <div className="flex items-center gap-2 text-zinc-300">
          <Loader2 className="w-4 h-4 animate-spin" /> 正在测速…
        </div>
      );
    }

    if (status === 'error') {
      return (
        <div className="flex items-start gap-2 text-red-400">
          <AlertTriangle className="w-4 h-4 mt-0.5" />
          <span className="text-sm">{error}</span>
        </div>
      );
    }

    if (status === 'done' && result) {
      const hint = getQualityHint(result.mbps);
      return (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-green-400">
            <CheckCircle2 className="w-4 h-4" />
            <span className="font-semibold">{result.mbps.toFixed(2)} Mbps</span>
          </div>
          <div className="text-xs text-zinc-400">
            传输 {formatBytes(result.bytes)} / {(result.durationMs / 1000).toFixed(2)}s
          </div>
          <div className="text-sm text-zinc-200">流畅度：{hint.label}</div>
          <div className="text-xs text-zinc-400">{hint.detail}</div>
        </div>
      );
    }

    return <div className="text-sm text-zinc-500">点击开始测速。</div>;
  };

  return (
    <div className="absolute inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center px-4">
      <div className="w-full max-w-md bg-zinc-900 border border-zinc-800 rounded-2xl shadow-2xl overflow-hidden">
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-800">
          <div className="flex items-center gap-2 text-white font-bold">
            <Gauge className="w-5 h-5 text-indigo-400" />
            网络测速
          </div>
          <button
            onClick={onClose}
            className="p-1 text-white/70 hover:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500 rounded"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="p-5 space-y-4">
          <div className="text-xs text-zinc-500">测试样本</div>
          <div className="text-sm text-zinc-200 truncate">{sampleLabel}</div>

          <div className="bg-zinc-800/60 rounded-xl p-4">
            {renderResult()}
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={runTest}
              disabled={status === 'running'}
              className="flex-1 py-2.5 rounded-lg bg-indigo-600 hover:bg-indigo-700 disabled:opacity-60 disabled:cursor-not-allowed text-white text-sm font-semibold focus:outline-none focus:ring-2 focus:ring-indigo-400"
            >
              开始测速
            </button>
            <button
              onClick={onClose}
              className="flex-1 py-2.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-zinc-200 text-sm font-semibold focus:outline-none focus:ring-2 focus:ring-zinc-500"
            >
              关闭
            </button>
          </div>

          <div className="text-[11px] text-zinc-500">
            会下载约 {formatBytes(TEST_BYTES)} 的视频片段用于测速。
          </div>
        </div>
      </div>
    </div>
  );
};

export default SpeedTestModal;
