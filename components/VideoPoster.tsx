import React, { useEffect, useMemo, useRef, useState } from 'react';
import { EmbyItem } from '../types';
import { MediaClient } from '../services/MediaClient';

interface VideoPosterProps {
  item: EmbyItem;
  client: MediaClient;
  className: string;
  alt?: string;
  style?: React.CSSProperties;
}

const VideoPoster: React.FC<VideoPosterProps> = ({ item, client, className, alt = '', style }) => {
  const [imgFailed, setImgFailed] = useState(false);
  const [videoFailed, setVideoFailed] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  const posterSrc = useMemo(() => {
    if (!item.ImageTags?.Primary) {
      return '';
    }
    return client.getImageUrl(item.Id, item.ImageTags.Primary, 'Primary');
  }, [client, item]);

  const videoSrc = useMemo(() => client.getVideoUrl(item), [client, item]);

  useEffect(() => {
    setImgFailed(false);
    setVideoFailed(false);
  }, [item.Id]);

  if (posterSrc && !imgFailed) {
    return (
      <img
        src={posterSrc}
        alt={alt}
        className={className}
        style={style}
        loading="lazy"
        onError={() => setImgFailed(true)}
      />
    );
  }

  if (!videoFailed) {
    return (
      <video
        ref={videoRef}
        src={videoSrc}
        className={className}
        style={style}
        muted
        playsInline
        preload="metadata"
        onLoadedMetadata={() => {
          const video = videoRef.current;
          if (!video) return;
          try {
            if (video.currentTime < 0.05) {
              video.currentTime = 0.1;
            }
          } catch {
            // Ignore seek errors on metadata-only streams.
          }
        }}
        onError={() => setVideoFailed(true)}
      />
    );
  }

  return (
    <div style={style} className={`${className} bg-zinc-900 flex items-center justify-center text-zinc-600 text-xs`}>
      Media
    </div>
  );
};

export default VideoPoster;
