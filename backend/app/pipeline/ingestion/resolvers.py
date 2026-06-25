import os
import yt_dlp
import instaloader
from typing import List, Union, Tuple

def download_content(url: str, output_path: str, cookies_path: str = None) -> Tuple[str, Union[str, List[str]], str]:
    """
    Downloads content from the given URL.
    First tries yt-dlp (for video).
    If it fails or finds no video, tries instaloader (for images/carousels).

    Returns:
        (type, data, caption)
        type: "video" or "images"
        data: path to .mp4 OR list of paths to images
        caption: text caption of the post
    """
    # 1. Try yt-dlp first (for videos/reels)
    video_res = _download_yt_dlp(url, output_path, cookies_path)
    if video_res:
        video_path, caption = video_res
        return "video", video_path, caption

    # 2. Try Instaloader (for carousels/images)
    if "instagram.com" in url:
        image_res = _download_instaloader(url)
        if image_res:
            image_paths, caption = image_res
            return "images", image_paths, caption

    raise RuntimeError(f"Could not download content from {url} using any available method.")

def _download_yt_dlp(url: str, output_path: str, cookies_path: str = None) -> Union[Tuple[str, str], None]:
    opts = {
        "format": "bestvideo[ext=mp4]+bestaudio/best",
        "outtmpl": output_path,
        "merge_output_format": "mp4",
        "quiet": True,
        "no_warnings": True,
    }

    if cookies_path and os.path.exists(cookies_path):
        opts["cookiefile"] = cookies_path

    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            # Check if video formats exist before downloading
            info = ydl.extract_info(url, download=False)
            caption = info.get('description', '') or info.get('title', '')

            if not info.get('formats'):
                return None
            ydl.download([url])
            if os.path.exists(output_path):
                return output_path, caption
    except Exception:
        return None
    return None

def _download_instaloader(url: str) -> Union[Tuple[List[str], str], None]:
    import re
    # Extract shortcode
    match = re.search(r"/(?:p|reels|reel)/([^/?#&]+)", url)
    if not match:
        return None

    shortcode = match.group(1)
    loader = instaloader.Instaloader(
        download_pictures=True,
        download_videos=False, # We use yt-dlp for videos
        download_video_thumbnails=False,
        download_geotags=False,
        download_comments=False,
        save_metadata=False,
        compress_json=False,
        dirname_pattern="temp_images"
    )

    try:
        # Cleanup previous temp folder
        import shutil
        if os.path.exists("temp_images"):
            shutil.rmtree("temp_images")

        post = instaloader.Post.from_shortcode(loader.context, shortcode)
        caption = post.caption or ""
        loader.download_post(post, target="temp_images")

        # Collect image paths
        images = [
            os.path.join("temp_images", f)
            for f in os.listdir("temp_images")
            if f.endswith((".jpg", ".png", ".webp"))
        ]
        if images:
            return sorted(images), caption
        return None
    except Exception as e:
        print(f"[Downloader] Instaloader failed: {e}")
        return None

# Keep compatibility for existing calls if any
def download_video(url: str, output_path: str, cookies_path: str = None) -> str:
    res_type, res_data, _ = download_content(url, output_path, cookies_path)
    if res_type == "video":
        return res_data
    raise RuntimeError("Download found images instead of video.")
