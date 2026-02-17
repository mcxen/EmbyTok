
import React, { useState, useEffect } from 'react';
import { EmbyLibrary, FeedType, OrientationMode } from '../types';
import { X, Folder, Settings, LogOut, Eye, EyeOff, ChevronLeft, Server, User, Smartphone, Monitor } from 'lucide-react';

interface LibrarySelectProps {
  libraries: EmbyLibrary[];
  onSelect: (lib: EmbyLibrary | null) => void;
  selectedId: string | null;
  onClose: () => void;
  isOpen: boolean;
  
  // Settings Mode Props
  hiddenLibIds: Set<string>;
  onToggleHidden: (libId: string) => void;
  onLogout: () => void;
  serverUrl: string;
  username: string;

  feedType: FeedType;
  onFeedTypeChange: (type: FeedType) => void;
  showFeedControls?: boolean;
  onOpenSpeedTest?: () => void;
  
  orientationMode: OrientationMode;
  onOrientationChange: (mode: OrientationMode) => void;

  isFolderServer?: boolean;
  onOpenAdminPanel?: () => void;
}

type MenuMode = 'list' | 'settings';

const LibrarySelect: React.FC<LibrarySelectProps> = ({ 
    libraries, 
    onSelect, 
    selectedId, 
    onClose, 
    isOpen,
    hiddenLibIds,
    onToggleHidden,
    onLogout,
  serverUrl,
  username,
  feedType,
  onFeedTypeChange,
  showFeedControls = false,
  onOpenSpeedTest,
  orientationMode,
  onOrientationChange,
  isFolderServer = false,
  onOpenAdminPanel
}) => {
  const [mode, setMode] = useState<MenuMode>('list');

  // Reset to list mode whenever drawer opens/closes
  useEffect(() => {
      if (!isOpen) {
          setTimeout(() => setMode('list'), 300);
      }
  }, [isOpen]);

  if (!isOpen) return null;

  const handleOpenAdmin = () => {
      if (!isFolderServer || !onOpenAdminPanel) return;
      const password = window.prompt('请输入管理员密码');
      if (password === null) return;
      if (password !== 'admin') {
          window.alert('管理员密码错误');
          return;
      }
      onOpenAdminPanel();
      onClose();
  };

  const handleFeedSelect = (type: FeedType) => {
      onFeedTypeChange(type);
      onClose();
  };

  const handleOpenSpeedTest = () => {
      if (!onOpenSpeedTest) return;
      onOpenSpeedTest();
      onClose();
  };

  return (
    <div className="absolute inset-0 z-50 bg-black/80 backdrop-blur-sm flex justify-start">
      <div className="w-3/4 max-w-sm h-full bg-zinc-900 border-r border-zinc-800 shadow-2xl flex flex-col animate-in slide-in-from-left duration-200">
        
        {/* HEADER */}
        <div className="p-4 border-b border-zinc-800 flex justify-between items-center bg-zinc-900 z-10">
          {mode === 'list' ? (
              <h2 className="text-white font-bold text-xl">媒体库</h2>
          ) : (
              <div className="flex items-center gap-2">
                  <button onClick={() => setMode('list')} className="p-1 -ml-2 text-zinc-400 hover:text-white focus:outline-none focus:ring-2 focus:ring-indigo-500 rounded">
                      <ChevronLeft className="w-6 h-6" />
                  </button>
                  <h2 className="text-white font-bold text-xl">设置</h2>
              </div>
          )}
          
          <button onClick={onClose} className="text-white/70 hover:text-white p-1 focus:outline-none focus:ring-2 focus:ring-indigo-500 rounded">
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* CONTENT AREA */}
        <div className="flex-1 overflow-y-auto p-2 scrollbar-thin scrollbar-thumb-zinc-700">
          
          {/* --- LIST MODE --- */}
          {mode === 'list' && (
              <>
                {showFeedControls && (
                  <div className="px-2 pt-2 pb-3">
                      <h3 className="text-xs font-bold text-zinc-500 uppercase tracking-wider px-1 mb-2">内容</h3>
                      <div className="bg-zinc-800 rounded-xl p-1 flex">
                          <button 
                            onClick={() => handleFeedSelect('favorites')}
                            className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${feedType === 'favorites' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
                          >
                              收藏
                          </button>
                          <button 
                            onClick={() => handleFeedSelect('random')}
                            className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${feedType === 'random' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
                          >
                              随机
                          </button>
                          <button 
                            onClick={() => handleFeedSelect('latest')}
                            className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${feedType === 'latest' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
                          >
                              最新
                          </button>
                      </div>
                  </div>
                )}
                <button
                    onClick={() => {
                        onSelect(null);
                        onClose();
                    }}
                    className={`w-full text-left p-4 rounded-xl mb-2 flex items-center gap-3 transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${
                    selectedId === null ? 'bg-indigo-600 text-white' : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'
                    }`}
                >
                    <Folder className="w-5 h-5 shrink-0" />
                    <span className="font-medium">所有媒体</span>
                </button>
                
                {libraries.filter(lib => !hiddenLibIds.has(lib.Id)).map((lib) => (
                    <button
                    key={lib.Id}
                    onClick={() => {
                        onSelect(lib);
                        onClose();
                    }}
                    className={`w-full text-left p-4 rounded-xl mb-2 flex items-center gap-3 transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${
                        selectedId === lib.Id ? 'bg-indigo-600 text-white' : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'
                    }`}
                    >
                    <Folder className="w-5 h-5 shrink-0" />
                    <span className="font-medium truncate">{lib.Name}</span>
                    </button>
                ))}
              </>
          )}

          {/* --- SETTINGS MODE --- */}
          {mode === 'settings' && (
              <div className="space-y-6 p-2">
                  
                  {/* Orientation Settings */}
                  <div className="space-y-3">
                      <h3 className="text-xs font-bold text-zinc-500 uppercase tracking-wider px-1">显示偏好</h3>
                      <div className="bg-zinc-800 rounded-xl p-1 flex">
                           <button 
                             onClick={() => onOrientationChange('vertical')}
                             className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${orientationMode === 'vertical' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
                           >
                               仅竖屏
                           </button>
                           <button 
                             onClick={() => onOrientationChange('horizontal')}
                             className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${orientationMode === 'horizontal' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
                           >
                               仅横屏
                           </button>
                           <button 
                             onClick={() => onOrientationChange('both')}
                             className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${orientationMode === 'both' ? 'bg-indigo-600 text-white shadow' : 'text-zinc-400 hover:text-zinc-200'}`}
                           >
                               全部
                           </button>
                      </div>
                      <p className="text-[10px] text-zinc-500 px-1">控制要在视频流中显示的视频类型。</p>
                  </div>

                  {/* Server Info Section */}
                  <div className="space-y-3">
                      <h3 className="text-xs font-bold text-zinc-500 uppercase tracking-wider px-1">连接信息</h3>
                      <div className="bg-zinc-800 rounded-xl p-4 space-y-3">
                          <div className="flex items-center gap-3 text-zinc-300">
                              <Server className="w-4 h-4 text-indigo-400" />
                              <span className="text-sm truncate opacity-80">{serverUrl}</span>
                          </div>
                          <div className="flex items-center gap-3 text-zinc-300">
                              <User className="w-4 h-4 text-indigo-400" />
                              <span className="text-sm truncate font-bold">{username}</span>
                          </div>
                          
                          <div className="pt-2 border-t border-zinc-700/50">
                              {onOpenSpeedTest && (
                                <button
                                  onClick={handleOpenSpeedTest}
                                  className="w-full mb-2 py-2.5 rounded-lg bg-indigo-500/10 hover:bg-indigo-500/20 text-indigo-300 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-400"
                                >
                                  网络测速
                                </button>
                              )}
                              {isFolderServer && (
                                <button
                                  onClick={handleOpenAdmin}
                                  className="w-full mb-2 py-2.5 rounded-lg bg-cyan-500/10 hover:bg-cyan-500/20 text-cyan-300 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-cyan-400"
                                >
                                  管理员面板
                                </button>
                              )}
                              <button 
                                onClick={onLogout}
                                className="w-full py-2.5 rounded-lg bg-red-500/10 hover:bg-red-500/20 text-red-400 text-sm font-medium flex items-center justify-center gap-2 transition-colors focus:outline-none focus:ring-2 focus:ring-red-500"
                              >
                                  <LogOut className="w-4 h-4" /> 断开连接
                              </button>
                          </div>
                      </div>
                  </div>

                  {/* Library Visibility Section */}
                  <div className="space-y-3">
                      <h3 className="text-xs font-bold text-zinc-500 uppercase tracking-wider px-1">媒体库管理</h3>
                      <p className="text-[10px] text-zinc-500 px-1 -mt-2 pb-1">点击眼睛图标隐藏/显示媒体库</p>
                      
                      <div className="space-y-1">
                          {libraries.map((lib) => {
                              const isHidden = hiddenLibIds.has(lib.Id);
                              return (
                                  <div key={lib.Id} className="flex items-center justify-between p-3 bg-zinc-800/50 rounded-lg">
                                      <div className="flex items-center gap-3 text-zinc-200">
                                          <Folder className={`w-4 h-4 ${isHidden ? 'text-zinc-600' : 'text-zinc-400'}`} />
                                          <span className={`text-sm ${isHidden ? 'text-zinc-500 line-through' : ''}`}>{lib.Name}</span>
                                      </div>
                                      <button 
                                        onClick={() => onToggleHidden(lib.Id)}
                                        className={`p-2 rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 ${isHidden ? 'text-zinc-600 hover:text-zinc-400' : 'text-indigo-400 hover:text-indigo-300 bg-indigo-500/10'}`}
                                      >
                                          {isHidden ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                                      </button>
                                  </div>
                              );
                          })}
                      </div>
                  </div>
              </div>
          )}
        </div>

        {/* BOTTOM FOOTER (Only in List Mode) */}
        {mode === 'list' && (
            <div className="p-4 border-t border-zinc-800 bg-zinc-900">
                <button 
                    onClick={() => setMode('settings')}
                    className="flex items-center gap-3 w-full p-3 text-zinc-400 hover:text-white hover:bg-zinc-800 rounded-xl transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500"
                >
                    <Settings className="w-5 h-5" />
                    <span className="font-medium">设置</span>
                </button>
            </div>
        )}

      </div>
       {/* Click outside to close */}
       <div className="flex-grow h-full cursor-pointer bg-transparent" onClick={onClose}></div>
    </div>
  );
};

export default LibrarySelect;
