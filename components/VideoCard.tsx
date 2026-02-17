
import React, { useRef, useEffect, useState } from 'react';
import { EmbyItem } from '../types';
import { MediaClient } from '../services/MediaClient';
import { Play, Pause, AlertCircle, Heart, Info, Disc, ChevronsRight, Rewind, FastForward, Zap, Infinity, RotateCw } from 'lucide-react';
import VideoPoster from './VideoPoster';

interface VideoCardProps {
  item: EmbyItem;
  client: MediaClient;
  isActive: boolean;
  isFavorite: boolean;
  onToggleFavorite: () => void;
  isMuted: boolean;
  onToggleMute: () => void;
  isAutoPlay?: boolean;
  onToggleAutoPlay?: () => void;
  onVideoEnd?: () => void;
  forceSwipeAutoplay?: boolean;
}

const VideoCard: React.FC<VideoCardProps> = ({ 
    item, 
    client, 
    isActive, 
    isFavorite, 
    onToggleFavorite,
    isMuted,
    onToggleMute,
    isAutoPlay = false,
    onToggleAutoPlay = () => {},
    onVideoEnd = () => {},
    forceSwipeAutoplay = false,
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const playRetryTimerRef = useRef<number | null>(null);
  const autoplayMutedFallbackRef = useRef(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [hasStarted, setHasStarted] = useState(false); 
  const [error, setError] = useState<string | null>(null);
  const [showInfo, setShowInfo] = useState(false);
  const [rotationDeg, setRotationDeg] = useState(0);
  const [isNarrowViewport, setIsNarrowViewport] = useState(() =>
    typeof window !== 'undefined' ? window.innerWidth <= 768 : false
  );
  
  // Progress State
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [isSeeking, setIsSeeking] = useState(false);

  // Gesture State
  const [playbackRate, setPlaybackRate] = useState(1.0);
  const [seekOffset, setSeekOffset] = useState<number | null>(null);
  
  // Screen Orientation State
  const [isScreenLandscape, setIsScreenLandscape] = useState(() => 
    typeof window !== 'undefined' ? window.innerWidth > window.innerHeight : false
  );
  
  // Gesture Refs
  const touchStartX = useRef(0);
  const touchStartY = useRef(0);
  const isDragging = useRef(false);
  const isLongPress = useRef(false);
  const longPressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ignoreNextClickRef = useRef(false);

  const videoSrc = client.getVideoUrl(item);
  const posterSrc = item.ImageTags?.Primary 
    ? client.getImageUrl(item.Id, item.ImageTags.Primary, 'Primary') 
    : undefined;
    
  const isContentLandscape = (item.Width || 0) > (item.Height || 0);

  useEffect(() => {
      const handleResize = () => {
          setIsScreenLandscape(window.innerWidth > window.innerHeight);
          setIsNarrowViewport(window.innerWidth <= 768);
      };
      window.addEventListener('resize', handleResize);
      return () => window.removeEventListener('resize', handleResize);
  }, []);

  useEffect(() => {
      setRotationDeg(0);
      autoplayMutedFallbackRef.current = false;
  }, [item.Id]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    
    video.muted = isMuted;

    const clearPlayRetry = () => {
      if (playRetryTimerRef.current !== null) {
        window.clearTimeout(playRetryTimerRef.current);
        playRetryTimerRef.current = null;
      }
    };

    const tryPlay = (attempt: number = 0) => {
      if (!isActive || !videoRef.current) {
        return;
      }

      const targetVideo = videoRef.current;
      const playPromise = targetVideo.play();
      if (playPromise === undefined) {
        setIsPlaying(!targetVideo.paused);
        return;
      }

      playPromise
        .then(() => {
          clearPlayRetry();
          setIsPlaying(true);
        })
        .catch((err) => {
          if (!isActive || !videoRef.current) {
            return;
          }

          if (
            forceSwipeAutoplay &&
            !autoplayMutedFallbackRef.current &&
            !videoRef.current.muted
          ) {
            autoplayMutedFallbackRef.current = true;
            videoRef.current.muted = true;
            if (!isMuted) {
              onToggleMute();
            }
          }

          if (forceSwipeAutoplay && attempt < 4) {
            clearPlayRetry();
            playRetryTimerRef.current = window.setTimeout(() => {
              tryPlay(attempt + 1);
            }, 220);
            return;
          }

          console.warn("Autoplay failed", err);
          setIsPlaying(false);
        });
    };

    if (isActive) {
      setError(null);
      video.playbackRate = 1.0;
      setPlaybackRate(1.0);
      tryPlay();
      
      // CRITICAL FIX: preventScroll: true prevents the browser from jumping the scroll position
      containerRef.current?.focus({ preventScroll: true });
    } else {
      clearPlayRetry();
      video.pause();
      video.currentTime = 0;
      setIsPlaying(false);
      setHasStarted(false); 
    }

    return () => {
      clearPlayRetry();
    };
  }, [isActive, isMuted, forceSwipeAutoplay]);

  const togglePlay = () => {
    const video = videoRef.current;
    if (!video) return;

    if (video.paused) {
      video.play();
      setIsPlaying(true);
    } else {
      video.pause();
      setIsPlaying(false);
    }
  };

  const handlePlaying = () => {
      setIsPlaying(true);
      setHasStarted(true); 
  };

  const handleTimeUpdate = () => {
      if (videoRef.current && !isSeeking) {
          setCurrentTime(videoRef.current.currentTime);
      }
  };

  const handleLoadedMetadata = () => {
      if (videoRef.current) {
          const nextDuration = Number.isFinite(videoRef.current.duration) ? videoRef.current.duration : 0;
          setDuration(nextDuration);
      }
  };

  const handleCanPlay = () => {
      if (!isActive) return;
      if (!videoRef.current) return;
      if (!videoRef.current.paused) return;
      const playPromise = videoRef.current.play();
      if (playPromise !== undefined) {
          playPromise
            .then(() => setIsPlaying(true))
            .catch(() => {
              // ignore here; main autoplay retry path is handled in effect
            });
      }
  };

  const handleVideoEnded = () => {
      if (isAutoPlay) {
          onVideoEnd();
      }
  };

  // --- Button Handlers with Robust Touch Support ---
  
  const handleButtonAction = (e: React.TouchEvent | React.MouseEvent | React.KeyboardEvent, action: () => void) => {
      e.stopPropagation();
      if (e.type === 'touchend') {
          e.preventDefault(); 
      }
      action();
  };

  const stopProp = (e: React.TouchEvent | React.MouseEvent | React.KeyboardEvent) => {
      e.stopPropagation();
  };

  const handleContextMenu = (e: React.MouseEvent | React.TouchEvent) => {
      e.preventDefault();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
      switch(e.key) {
          case 'Enter':
          case ' ':
              togglePlay();
              break;
          case 'ArrowLeft':
              if (videoRef.current) videoRef.current.currentTime -= 10;
              break;
          case 'ArrowRight':
              if (videoRef.current) videoRef.current.currentTime += 10;
              break;
          case 'm':
              onToggleMute();
              break;
          case 'f':
              onToggleFavorite();
              break;
      }
  };

  // --- Seek Bar Handlers ---
  const handleSeekStart = (e: React.TouchEvent | React.MouseEvent) => {
      e.stopPropagation();
      setIsSeeking(true);
  };

  const handleSeekEnd = (e: React.TouchEvent | React.MouseEvent) => {
      e.stopPropagation();
      setIsSeeking(false);
  };

  const handleSeekChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      const nextTime = Number(e.target.value);
      setCurrentTime(nextTime);
      if (videoRef.current) {
          videoRef.current.currentTime = nextTime;
      }
  };

  const handleContainerClick = () => {
      if (ignoreNextClickRef.current) {
          ignoreNextClickRef.current = false;
          return;
      }
      togglePlay();
  };

  // --- Gesture Handlers ---

  const handleTouchStart = (e: React.TouchEvent) => {
      touchStartX.current = e.touches[0].clientX;
      touchStartY.current = e.touches[0].clientY;
      isDragging.current = false;
      isLongPress.current = false;
      setSeekOffset(null);

      longPressTimer.current = setTimeout(() => {
          isLongPress.current = true;
          setPlaybackRate(2.0);
          if (videoRef.current) videoRef.current.playbackRate = 2.0;
      }, 500);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
      const currentX = e.touches[0].clientX;
      const currentY = e.touches[0].clientY;
      const deltaX = currentX - touchStartX.current;
      const deltaY = currentY - touchStartY.current;

      if (Math.abs(deltaX) > 10 || Math.abs(deltaY) > 10) {
          if (longPressTimer.current) {
              clearTimeout(longPressTimer.current);
              longPressTimer.current = null;
          }
      }

      if (!isLongPress.current && Math.abs(deltaX) > 20 && Math.abs(deltaX) > Math.abs(deltaY)) {
           isDragging.current = true;
           const offset = Math.round(deltaX / 5); 
           setSeekOffset(offset);
      }
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
      if (longPressTimer.current) {
          clearTimeout(longPressTimer.current);
          longPressTimer.current = null;
      }

      ignoreNextClickRef.current = true;

      const deltaX = e.changedTouches[0].clientX - touchStartX.current;
      const deltaY = e.changedTouches[0].clientY - touchStartY.current;

      if (isLongPress.current) {
          isLongPress.current = false;
          setPlaybackRate(1.0);
          if (videoRef.current) videoRef.current.playbackRate = 1.0;
      } else if (isDragging.current) {
          if (videoRef.current && seekOffset !== null) {
              const newTime = videoRef.current.currentTime + seekOffset;
              videoRef.current.currentTime = Math.min(Math.max(newTime, 0), videoRef.current.duration);
          }
          isDragging.current = false;
          setSeekOffset(null);
      } else {
          if (Math.abs(deltaX) < 10 && Math.abs(deltaY) < 10) {
              togglePlay();
          }
      }
  };

  const formatTimeText = (ticks?: number) => {
      if (!ticks) return '';
      const minutes = Math.round(ticks / 10000000 / 60);
      return `${minutes} 分钟`;
  }

  const showBlurBackground = isScreenLandscape && !isContentLandscape;
  
  const videoObjectFitClass = (isNarrowViewport || isScreenLandscape || isContentLandscape) 
      ? 'object-contain' 
      : 'object-cover';
  const isVideoRotated = rotationDeg % 180 !== 0;
  const rotatedVideoStyle: React.CSSProperties = isVideoRotated
      ? {
          transform: `rotate(${rotationDeg}deg)`,
          width: '100dvh',
          height: '100dvw',
        }
      : {
          transform: `rotate(${rotationDeg}deg)`,
        };
  const safeDuration = Number.isFinite(duration) ? duration : 0;
  const safeCurrentTime = Math.min(currentTime, safeDuration);

  // Render UI elements only if NOT in AutoPlay (Pure) Mode
  const renderUI = !isAutoPlay;

  return (
    <div 
        ref={containerRef}
        tabIndex={isActive ? 0 : -1}
        className="relative w-full h-full bg-black snap-start shrink-0 flex items-center justify-center overflow-hidden touch-pan-y select-none focus:outline-none"
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
        onClick={handleContainerClick}
        onContextMenu={handleContextMenu}
        onKeyDown={handleKeyDown}
    >
      {/* Blurred Background Layer for Vertical Videos in Landscape Mode */}
      {showBlurBackground && posterSrc && (
          <div className="absolute inset-0 w-full h-full overflow-hidden z-0">
               <img 
                  src={posterSrc} 
                  alt="" 
                  className="w-full h-full object-cover blur-2xl opacity-40 scale-110" 
               />
               <div className="absolute inset-0 bg-black/30"></div>
          </div>
      )}

      {/* Video Element */}
      <video
        ref={videoRef}
        className={`w-full h-full pointer-events-none relative z-10 bg-transparent ${videoObjectFitClass}`}
        style={rotatedVideoStyle}
        src={videoSrc}
        loop={!isAutoPlay} // Disable loop in AutoPlay mode to trigger onEnded
        playsInline
        autoPlay
        muted={isMuted}
        onPlaying={handlePlaying}
        onTimeUpdate={handleTimeUpdate}
        onLoadedMetadata={handleLoadedMetadata}
        onCanPlay={handleCanPlay}
        onEnded={handleVideoEnded}
        onError={() => setError("无法加载视频")}
      />

      {/* Manual Poster Overlay */}
      {!hasStarted && (
        <VideoPoster
          item={item}
          client={client}
          className={`absolute inset-0 w-full h-full z-10 bg-transparent pointer-events-none ${videoObjectFitClass}`}
          style={rotatedVideoStyle}
          alt=""
        />
      )}

      {/* Play/Pause Overlay Icon */}
      {!isPlaying && !error && !seekOffset && !isLongPress.current && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-20">
          <Play className="w-16 h-16 text-white/40 fill-white/20" />
        </div>
      )}

      {/* 2x Speed Overlay */}
      {playbackRate > 1.0 && (
          <div className="absolute top-24 left-0 right-0 flex justify-center z-50 pointer-events-none">
            <div className="flex items-center gap-2 bg-black/60 backdrop-blur-sm px-4 py-2 rounded-full">
                <Zap className="w-4 h-4 text-yellow-400 fill-yellow-400" />
                <span className="text-white font-bold text-sm">2倍速中</span>
                <ChevronsRight className="w-4 h-4 text-white" />
            </div>
          </div>
      )}

      {/* Seek Overlay */}
      {seekOffset !== null && (
          <div className="absolute top-24 left-0 right-0 flex flex-col items-center justify-start z-50 pointer-events-none">
              <div className="flex flex-col items-center gap-1 bg-black/40 backdrop-blur-md px-4 py-2 rounded-xl">
                  {seekOffset > 0 ? (
                       <FastForward className="w-6 h-6 text-white/90 fill-white/20" />
                  ) : (
                       <Rewind className="w-6 h-6 text-white/90 fill-white/20" />
                  )}
                  <div className="text-lg font-bold text-white drop-shadow-lg">
                      {seekOffset > 0 ? '+' : ''}{seekOffset}s
                  </div>
              </div>
          </div>
      )}
      
      {/* Toast Notification Removed from here to prevent duplicate alerts */}

      {error && (
        <div className="absolute inset-0 flex flex-col items-center justify-center bg-gray-900 text-white p-4 z-10">
          <AlertCircle className="w-12 h-12 text-red-500 mb-2" />
          <p className="text-center">{error}</p>
        </div>
      )}
      
      {/* Auto Play Toggle Button (Always Visible) */}
      <div className="absolute bottom-8 right-2 z-40 w-12 flex flex-col items-center justify-center pointer-events-auto">
          <button
            onTouchStart={stopProp} 
            onMouseDown={stopProp}
            onTouchEnd={(e) => handleButtonAction(e, onToggleAutoPlay)}
            onClick={(e) => handleButtonAction(e, onToggleAutoPlay)}
            className={`p-2.5 rounded-full backdrop-blur-sm transition-all active:scale-90 focus:ring-2 focus:ring-green-500 outline-none shadow-lg ${isAutoPlay ? 'bg-green-500/80 text-white' : 'bg-black/30 text-white/50 hover:bg-black/50 hover:text-white'}`}
          >
              <Infinity className="w-6 h-6" />
          </button>
      </div>

      {/* RIGHT SIDEBAR ACTION BAR (Conditional) */}
      {renderUI && (
          <div className="absolute right-2 bottom-24 flex flex-col items-center gap-6 z-30 pointer-events-auto">
              <div className="relative w-12 h-12 mb-2">
                  <div className="w-12 h-12 rounded-full border-2 border-white overflow-hidden bg-zinc-800">
                      <VideoPoster
                        item={item}
                        client={client}
                        alt="Poster"
                        className="w-full h-full object-cover"
                      />
                  </div>
              </div>

              <div className="flex flex-col items-center gap-1">
                  <button 
                    tabIndex={0}
                    onTouchStart={stopProp} 
                    onMouseDown={stopProp}
                    onTouchEnd={(e) => handleButtonAction(e, onToggleFavorite)}
                    onClick={(e) => handleButtonAction(e, onToggleFavorite)}
                    className="p-2 rounded-full transition-transform active:scale-75 focus:ring-2 focus:ring-indigo-500 outline-none"
                  >
                      <Heart 
                        className={`w-8 h-8 drop-shadow-md transition-colors duration-300 ${isFavorite ? 'fill-red-500 text-red-500' : 'text-white fill-transparent'}`} 
                        strokeWidth={isFavorite ? 0 : 2}
                      />
                  </button>
                  <span className="text-white text-xs font-bold shadow-black drop-shadow-md">
                    {isFavorite ? '已赞' : '点赞'}
                  </span>
              </div>

              <div className="flex flex-col items-center gap-1">
                  <button 
                    tabIndex={0}
                    onTouchStart={stopProp}
                    onMouseDown={stopProp}
                    onTouchEnd={(e) => handleButtonAction(e, () => setShowInfo(!showInfo))}
                    onClick={(e) => handleButtonAction(e, () => setShowInfo(!showInfo))}
                    className="p-2 rounded-full bg-white/10 backdrop-blur-sm active:bg-white/20 focus:ring-2 focus:ring-indigo-500 outline-none"
                  >
                      <Info className="w-7 h-7 text-white drop-shadow-md" />
                  </button>
                  <span className="text-white text-xs font-bold shadow-black drop-shadow-md">信息</span>
              </div>

              <div className="flex flex-col items-center gap-1">
                  <button
                    tabIndex={0}
                    onTouchStart={stopProp}
                    onMouseDown={stopProp}
                    onTouchEnd={(e) => handleButtonAction(e, () => setRotationDeg((prev) => (prev + 90) % 360))}
                    onClick={(e) => handleButtonAction(e, () => setRotationDeg((prev) => (prev + 90) % 360))}
                    className="p-2 rounded-full bg-transparent active:bg-white/10 focus:ring-2 focus:ring-cyan-500 outline-none"
                  >
                      <RotateCw className="w-7 h-7 text-white/80 drop-shadow-md" />
                  </button>
                  <span className="text-white text-xs font-bold shadow-black drop-shadow-md">旋转</span>
              </div>

              <div 
                    tabIndex={0}
                    onTouchStart={stopProp}
                    onMouseDown={stopProp}
                    onTouchEnd={(e) => handleButtonAction(e, onToggleMute)}
                    onClick={(e) => handleButtonAction(e, onToggleMute)}
                    className={`mt-4 w-10 h-10 rounded-full bg-zinc-900 border-4 cursor-pointer transition-colors duration-300 flex items-center justify-center overflow-hidden focus:ring-2 focus:ring-indigo-500 outline-none ${isMuted ? 'border-red-500/80' : 'border-zinc-800'} ${isPlaying ? 'animate-[spin_4s_linear_infinite]' : ''}`}
              >
                    {posterSrc ? (
                        <img src={posterSrc} className="w-full h-full object-cover opacity-70" />
                    ) : (
                        <Disc className="w-6 h-6 text-zinc-500" />
                    )}
              </div>
          </div>
      )}

      {/* BOTTOM INFO (Conditional) */}
      {renderUI && (
          <div className={`absolute bottom-0 left-0 right-0 p-4 bg-gradient-to-t from-black/90 via-black/40 to-transparent transition-all duration-300 pointer-events-auto z-10 ${showInfo ? 'h-2/3 from-black/95' : 'pt-24'}`}>
            <div className="flex flex-col items-start max-w-[80%]">
                <h3 className="text-white font-bold text-lg drop-shadow-md mb-2 leading-tight">
                  {item.Name}
                </h3>
                
                <div className="flex items-center gap-3 text-xs text-white/90 mb-2 font-medium drop-shadow-md">
                  {item.ProductionYear && <span className="bg-white/20 px-1.5 py-0.5 rounded">{item.ProductionYear}</span>}
                  <span>{formatTimeText(item.RunTimeTicks)}</span>
                  <span className="uppercase border border-white/30 px-1 rounded text-[10px]">{item.MediaType || '视频'}</span>
                </div>

                <div 
                    tabIndex={showInfo ? 0 : -1}
                    onTouchStart={stopProp}
                    onMouseDown={stopProp}
                    onTouchEnd={(e) => handleButtonAction(e, () => setShowInfo(!showInfo))}
                    onClick={(e) => handleButtonAction(e, () => setShowInfo(!showInfo))}
                    className={`text-white/80 text-sm drop-shadow-md transition-all duration-300 cursor-pointer focus:ring-1 focus:ring-white/50 rounded ${showInfo ? 'line-clamp-none overflow-y-auto max-h-[40vh]' : 'line-clamp-2'}`}
                >
                    {item.Overview || '暂无简介'}
                </div>
            </div>
          </div>
      )}

      {/* Progress Bar (Conditional) */}
      {renderUI && safeDuration > 0 && (
          <div
            className="absolute left-0 right-0 bottom-0 px-3 pb-2 z-50 pointer-events-auto"
            onClick={(e) => e.stopPropagation()}
            onTouchStart={stopProp}
            onMouseDown={stopProp}
          >
              <div className="flex items-center gap-2">
                  <button
                    onTouchStart={stopProp}
                    onMouseDown={stopProp}
                    onTouchEnd={(e) => handleButtonAction(e, togglePlay)}
                    onClick={(e) => handleButtonAction(e, togglePlay)}
                    className="p-1.5 rounded-full text-white/65 hover:text-white transition-colors bg-transparent focus:ring-2 focus:ring-white/40 outline-none"
                  >
                      {isPlaying ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5" />}
                  </button>
                  <input
                    type="range"
                    min={0}
                    max={safeDuration}
                    step={0.01}
                    value={safeCurrentTime}
                    onChange={handleSeekChange}
                    onMouseDown={handleSeekStart}
                    onMouseUp={handleSeekEnd}
                    onTouchStart={handleSeekStart}
                    onTouchEnd={handleSeekEnd}
                    className="embytok-progress-slider"
                  />
              </div>
          </div>
      )}
    </div>
  );
};

export default VideoCard;
