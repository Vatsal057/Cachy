import json
import logging
import re
import shutil
import ssl
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import List, Optional, Tuple, Union

import instaloader
import requests
import yt_dlp

ssl._create_default_https_context = ssl._create_unverified_context
log = logging.getLogger("ingestion.resolvers")


def _is_valid_video_link(link: Optional[str]) -> bool:
    """Checks if the extracted media link points to a video stream rather than an image."""
    if not link:
        return False
    low = link.lower()
    image_indicators = [".jpg", ".jpeg", ".png", ".webp", "dst-jpg", "image_urlgen", "format=jpg"]
    if any(ind in low for ind in image_indicators):
        return False
    return True


def download_content(
    url: str, output_path: Union[str, Path], cookies_path: Optional[Union[str, Path]] = None
) -> Tuple[str, Union[str, List[str]], str]:
    """Downloads content from the given URL.
    First tries keyless scrapers (vidssave, savethevideo, saveig, downloadgram, anyvidsave, igreelsdl).
    If they fail, tries yt-dlp (for video).
    If it fails or finds no video, tries instaloader (for images/carousels).

    Args:
        url: Source URL to ingest.
        output_path: Target filesystem path for downloaded video.
        cookies_path: Optional path to netscape cookie file.

    Returns:
        Tuple of (media_type, data_path_or_list, caption).
    """
    # 1. Try keyless scrapers first (in cascade order)
    keyless_funcs = [
        ("vidssave", _download_vidssave),
        ("savethevideo", _download_savethevideo),
        ("saveig", _download_saveig),
        ("downloadgram", _download_downloadgram),
        ("anyvidsave", _download_anyvidsave),
        ("igreelsdl", _download_igreelsdl),
    ]
    for name, scraper_fn in keyless_funcs:
        try:
            res = scraper_fn(url, output_path)
            if res:
                media_type, data, caption = res
                return media_type, data, caption
        except Exception as e:
            log.warning(f"Keyless resolver {name} failed in download_content for {url}: {e}")

    # 2. Try yt-dlp (for videos/reels)
    video_res = _download_yt_dlp(url, output_path, cookies_path)
    if video_res:
        video_path, caption = video_res
        return "video", video_path, caption

    # 3. Try Instaloader (for carousels/images)
    if "instagram.com" in url:
        image_res = _download_instaloader(url)
        if image_res:
            image_paths, caption = image_res
            return "images", image_paths, caption

    raise RuntimeError(f"Could not download content from {url} using any available method.")


def _download_vidssave(
    url: str, output_path: Union[str, Path]
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Resolves URL using the public vidssave.com API.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    api_url = "https://api.vidssave.com/api/contentsite_api/media/parse"
    headers = {
        "accept": "*/*",
        "accept-language": "en-US,en;q=0.9",
        "content-type": "application/x-www-form-urlencoded",
        "origin": "https://vidssave.com",
        "referer": "https://vidssave.com/",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    }
    data = {
        "auth": "20250901majwlqo",
        "domain": "api-ak.vidssave.com",
        "origin": "source",
        "link": url,
    }
    try:
        response = requests.post(api_url, headers=headers, data=data, timeout=20)
        if response.status_code == 200:
            res_json = response.json()
            media_data = res_json.get("data", {})
            caption = media_data.get("title", "")
            resources = media_data.get("resources", [])
            if resources:
                first_url = resources[0].get("download_url")
                if _is_valid_video_link(first_url):
                    log.debug(f"[vidssave] Got direct link: {first_url[:60] if first_url else ''}...")
                    video_response = requests.get(
                        first_url, stream=True, headers={"user-agent": headers["user-agent"]}, timeout=60
                    )
                    if video_response.status_code == 200:
                        target_path.parent.mkdir(parents=True, exist_ok=True)
                        with target_path.open("wb") as f:
                            for chunk in video_response.iter_content(chunk_size=8192):
                                if chunk:
                                    f.write(chunk)
                        if target_path.exists() and target_path.stat().st_size > 0:
                            return "video", str(target_path), caption
                    else:
                        log.warning(f"[vidssave] Download failed with stream status: {video_response.status_code}")
                else:
                    log.debug("[vidssave] Link points to images, saving as image carousel.")
                    saved_paths = []
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    base_stem = target_path.stem
                    for idx, res_dict in enumerate(resources, 1):
                        img_url = res_dict.get("download_url")
                        if not img_url:
                            continue
                        img_path = target_path.parent / f"{base_stem}_{idx}.jpg"
                        try:
                            img_resp = requests.get(
                                img_url, stream=True, headers={"user-agent": headers["user-agent"]}, timeout=30
                            )
                            if img_resp.status_code == 200:
                                with img_path.open("wb") as f:
                                    for chunk in img_resp.iter_content(chunk_size=8192):
                                        if chunk:
                                            f.write(chunk)
                                if img_path.exists() and img_path.stat().st_size > 0:
                                    saved_paths.append(str(img_path))
                        except Exception as img_err:
                            log.warning(f"[vidssave] Failed to download carousel image {idx}: {img_err}")
                    if saved_paths:
                        return "images", saved_paths, caption
            else:
                log.debug(f"[vidssave] API did not return resources: {res_json}")
        else:
            log.warning(f"[vidssave] API POST failed with status: {response.status_code}")
    except Exception as e:
        log.warning(f"[vidssave] Helper failed for {url}: {e}")
    return None


def _download_savethevideo(
    url: str, output_path: Union[str, Path]
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Resolves URL using the public savethevideo.com API by polling task status.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    api_url = "https://api.v02.savethevideo.com/tasks"
    headers = {
        "accept": "application/json",
        "content-type": "application/json",
        "origin": "https://www.savethevideo.com",
        "referer": "https://www.savethevideo.com/",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
    }
    payload = {"type": "info", "url": url}

    def download_from_result(result_list: list) -> Optional[Tuple[str, Union[str, List[str]], str]]:
        if not result_list:
            log.debug("[savethevideo] Task result is empty.")
            return None
        video_url = result_list[0].get("url")
        caption = result_list[0].get("description") or result_list[0].get("title", "")
        if _is_valid_video_link(video_url):
            log.debug(f"[savethevideo] Got direct link: {video_url[:60] if video_url else ''}...")
            try:
                video_response = requests.get(video_url, stream=True, timeout=60)
                if video_response.status_code == 200:
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    with target_path.open("wb") as f:
                        for chunk in video_response.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                    if target_path.exists() and target_path.stat().st_size > 0:
                        return "video", str(target_path), caption
                else:
                    log.warning(f"[savethevideo] Download failed with status: {video_response.status_code}")
            except Exception as e:
                log.warning(f"[savethevideo] Stream download failed: {e}")
        else:
            log.debug("[savethevideo] Link points to images, saving as image carousel.")
            saved_paths = []
            target_path.parent.mkdir(parents=True, exist_ok=True)
            base_stem = target_path.stem
            for idx, res_item in enumerate(result_list, 1):
                img_url = res_item.get("url")
                if not img_url:
                    continue
                img_path = target_path.parent / f"{base_stem}_{idx}.jpg"
                try:
                    img_resp = requests.get(img_url, stream=True, timeout=30)
                    if img_resp.status_code == 200:
                        with img_path.open("wb") as f:
                            for chunk in img_resp.iter_content(chunk_size=8192):
                                if chunk:
                                    f.write(chunk)
                        if img_path.exists() and img_path.stat().st_size > 0:
                            saved_paths.append(str(img_path))
                except Exception as img_err:
                    log.warning(f"[savethevideo] Failed to download image {idx}: {img_err}")
            if saved_paths:
                return "images", saved_paths, caption
        return None

    try:
        response = requests.post(api_url, headers=headers, json=payload, timeout=20)
        if response.status_code == 200:
            res_json = response.json()
            if res_json.get("state") == "completed":
                return download_from_result(res_json.get("result", []))
            log.debug(f"[savethevideo] State is {res_json.get('state')}")
        elif response.status_code == 202:
            res_json = response.json()
            task_id = res_json.get("id")
            if not task_id:
                log.warning("[savethevideo] Task created but no task ID returned.")
                return None
            poll_url = f"https://api.v02.savethevideo.com/tasks/{task_id}"
            log.debug(f"[savethevideo] Polling task: {poll_url}")
            for _ in range(15):
                poll_resp = requests.get(
                    poll_url,
                    headers={"accept": "application/json", "referer": "https://www.savethevideo.com/"},
                    timeout=15,
                )
                if poll_resp.status_code == 200:
                    poll_json = poll_resp.json()
                    state = poll_json.get("state")
                    if state == "completed":
                        return download_from_result(poll_json.get("result", []))
                    if state == "failed":
                        log.warning("[savethevideo] Task failed on remote server.")
                        return None
                time.sleep(2)
        else:
            log.warning(f"[savethevideo] Task creation failed with status: {response.status_code}")
    except Exception as e:
        log.warning(f"[savethevideo] Helper failed for {url}: {e}")
    return None


def _download_saveig(
    url: str, output_path: Union[str, Path]
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Resolves URL using the public saveig.in API.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    api_url = "https://saveig.in/wp-json/visolix/api/download"
    headers = {
        "accept": "application/json, text/plain, */*",
        "content-type": "application/json",
        "origin": "https://saveig.in",
        "referer": "https://saveig.in/fastdl/",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
    }
    payload = {"url": url, "format": "", "captcha_response": None}
    try:
        response = requests.post(api_url, headers=headers, json=payload, timeout=20)
        if response.status_code != 200:
            log.warning(f"[saveig] POST returned status code {response.status_code}")
            return None
        res_json = response.json()
        if not res_json.get("status"):
            log.debug(f"[saveig] API returned failure status: {res_json}")
            return None
        html_content = res_json.get("data", "")
        match = re.search(r'href=["\']([^"\']*dl\.php\?id=[a-zA-Z0-9]+)["\']', html_content)
        if not match:
            log.debug("[saveig] Could not find download link in HTML response data.")
            return None
        dl_url = match.group(1)
        if dl_url.startswith("/"):
            dl_url = "https://saveig.in" + dl_url
        elif dl_url.startswith("../"):
            dl_url = "https://saveig.in/wp-content/plugins/visolix-video-downloader/" + dl_url
        elif not dl_url.startswith("http"):
            dl_url = "https://saveig.in/wp-content/plugins/visolix-video-downloader/includes/" + dl_url
        dl_url = dl_url.replace("/includes/../", "/")
        if _is_valid_video_link(dl_url):
            log.debug(f"[saveig] Got proxy link: {dl_url[:60]}...")
            video_resp = requests.get(dl_url, stream=True, headers={"user-agent": headers["user-agent"]}, timeout=60)
            if video_resp.status_code != 200:
                log.warning(f"[saveig] Proxy stream returned status code {video_resp.status_code}")
                return None
            target_path.parent.mkdir(parents=True, exist_ok=True)
            with target_path.open("wb") as f:
                for chunk in video_resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            if target_path.exists() and target_path.stat().st_size > 0:
                return "video", str(target_path), ""
        else:
            log.debug("[saveig] Link points to image, saving as jpg.")
            target_path.parent.mkdir(parents=True, exist_ok=True)
            img_path = target_path.parent / f"{target_path.stem}_1.jpg"
            img_resp = requests.get(dl_url, stream=True, headers={"user-agent": headers["user-agent"]}, timeout=60)
            if img_resp.status_code == 200:
                with img_path.open("wb") as f:
                    for chunk in img_resp.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                if img_path.exists() and img_path.stat().st_size > 0:
                    return "images", [str(img_path)], ""
    except Exception as e:
        log.warning(f"[saveig] Helper failed for {url}: {e}")
    return None



def _download_downloadgram(
    url: str, output_path: Union[str, Path]
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Resolves URL using the public downloadgram.org API.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    api_url = "https://api.downloadgram.org/media"
    headers = {
        "accept": "*/*",
        "content-type": "application/x-www-form-urlencoded",
        "origin": "https://downloadgram.org",
        "referer": "https://downloadgram.org/",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
    }
    payload = {"url": url, "v": "3", "lang": "en"}
    try:
        response = requests.post(api_url, headers=headers, data=payload, timeout=20)
        if response.status_code != 200:
            log.warning(f"[downloadgram] POST returned status code {response.status_code}")
            return None
        matches = re.findall(r"https://cdn\.downloadgram\.org/\?token=[a-zA-Z0-9_\-\.]+", response.text)
        if not matches:
            log.debug("[downloadgram] Could not find CDN link in response.")
            return None
        dl_url = matches[-1]
        if _is_valid_video_link(dl_url):
            log.debug(f"[downloadgram] Got direct link: {dl_url[:60]}...")
            video_resp = requests.get(dl_url, headers={"user-agent": headers["user-agent"]}, stream=True, timeout=60)
            if video_resp.status_code != 200:
                log.warning(f"[downloadgram] Stream returned status code {video_resp.status_code}")
                return None
            target_path.parent.mkdir(parents=True, exist_ok=True)
            with target_path.open("wb") as f:
                for chunk in video_resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            if target_path.exists() and target_path.stat().st_size > 0:
                return "video", str(target_path), ""
        else:
            log.debug("[downloadgram] Link points to image, saving as jpg.")
            target_path.parent.mkdir(parents=True, exist_ok=True)
            img_path = target_path.parent / f"{target_path.stem}_1.jpg"
            img_resp = requests.get(dl_url, headers={"user-agent": headers["user-agent"]}, stream=True, timeout=60)
            if img_resp.status_code == 200:
                with img_path.open("wb") as f:
                    for chunk in img_resp.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                if img_path.exists() and img_path.stat().st_size > 0:
                    return "images", [str(img_path)], ""
    except Exception as e:
        log.warning(f"[downloadgram] Helper failed for {url}: {e}")
    return None


def _download_anyvidsave(
    url: str, output_path: Union[str, Path]
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Resolves URL using the public anyvidsave.in API.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    api_url = "https://anyvidsave.in/download.php"
    headers = {
        "Content-Type": "application/json",
        "Origin": "https://anyvidsave.in",
        "Referer": "https://anyvidsave.in/",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0",
    }
    data = {"url": url}
    try:
        response = requests.post(api_url, headers=headers, json=data, timeout=15)
        if response.status_code == 200:
            res_json = response.json()
            if res_json.get("success") and not res_json.get("limit_reached"):
                media_data = res_json.get("data", {})
                caption = media_data.get("title", "")
                links = media_data.get("links", [])
                cdn_url = None
                for link in links:
                    if link.get("type") == "mp4" or "video" in link.get("type", ""):
                        cdn_url = link.get("url")
                        break
                if cdn_url and _is_valid_video_link(cdn_url):
                    log.debug(f"[anyvidsave] Got CDN link: {cdn_url[:60]}...")
                    video_response = requests.get(cdn_url, stream=True, timeout=30)
                    if video_response.status_code == 200:
                        target_path.parent.mkdir(parents=True, exist_ok=True)
                        with target_path.open("wb") as f:
                            for chunk in video_response.iter_content(chunk_size=8192):
                                if chunk:
                                    f.write(chunk)
                        if target_path.exists() and target_path.stat().st_size > 0:
                            return "video", str(target_path), caption
                else:
                    log.debug("[anyvidsave] Link points to images, collecting image links.")
                    saved_paths = []
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    base_stem = target_path.stem
                    for idx, l_item in enumerate(links, 1):
                        img_url = l_item.get("url")
                        if not img_url or _is_valid_video_link(img_url):
                            continue
                        img_path = target_path.parent / f"{base_stem}_{idx}.jpg"
                        try:
                            img_resp = requests.get(img_url, stream=True, timeout=30)
                            if img_resp.status_code == 200:
                                with img_path.open("wb") as f:
                                    for chunk in img_resp.iter_content(chunk_size=8192):
                                        if chunk:
                                            f.write(chunk)
                                if img_path.exists() and img_path.stat().st_size > 0:
                                    saved_paths.append(str(img_path))
                        except Exception as img_err:
                            log.warning(f"[anyvidsave] Failed to download image {idx}: {img_err}")
                    if saved_paths:
                        return "images", saved_paths, caption
    except Exception as e:
        log.warning(f"[anyvidsave] Helper failed for {url}: {e}")
    return None


def _download_igreelsdl(
    url: str, output_path: Union[str, Path]
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Resolves URL using the public igreelsdl.com API.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    resolve_url = f"https://igreelsdl.com/api/resolve?url={requests.utils.quote(url)}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/120.0.0.0",
        "Referer": "https://igreelsdl.com/",
    }
    try:
        response = requests.get(resolve_url, headers=headers, timeout=15)
        if response.status_code == 200:
            res_json = response.json()
            if res_json.get("success"):
                caption = res_json.get("title", "")
                source_url = res_json.get("sourceUrl", url)
                formats = res_json.get("formats", [])
                format_id = formats[0].get("formatId", "best") if formats else "best"
                download_url = (
                    f"https://igreelsdl.com/api/download?"
                    f"url={requests.utils.quote(source_url)}&"
                    f"format_id={requests.utils.quote(format_id)}&"
                    f"filename=instagram-download.mp4&"
                    f"type=video"
                )
                if _is_valid_video_link(download_url):
                    log.debug(f"[igreelsdl] Got proxy link: {download_url[:60]}...")
                    video_response = requests.get(download_url, headers=headers, stream=True, timeout=30)
                    if video_response.status_code == 200:
                        target_path.parent.mkdir(parents=True, exist_ok=True)
                        with target_path.open("wb") as f:
                            for chunk in video_response.iter_content(chunk_size=8192):
                                if chunk:
                                    f.write(chunk)
                        if target_path.exists() and target_path.stat().st_size > 0:
                            return "video", str(target_path), caption
                else:
                    log.debug("[igreelsdl] Link points to image, saving as jpg.")
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    img_path = target_path.parent / f"{target_path.stem}_1.jpg"
                    img_resp = requests.get(download_url, headers=headers, stream=True, timeout=30)
                    if img_resp.status_code == 200:
                        with img_path.open("wb") as f:
                            for chunk in img_resp.iter_content(chunk_size=8192):
                                if chunk:
                                    f.write(chunk)
                        if img_path.exists() and img_path.stat().st_size > 0:
                            return "images", [str(img_path)], caption
    except Exception as e:
        log.warning(f"[igreelsdl] Helper failed for {url}: {e}")
    return None


def _download_rapidapi(
    url: str, output_path: Union[str, Path], api_key: str
) -> Optional[Tuple[str, Union[str, List[str]], str]]:
    """Uses a RapidAPI social media downloader to get the direct unblocked CDN link.

    Args:
        url: Source URL of the video/reel.
        output_path: Target filesystem path where the video should be saved.
        api_key: RapidAPI subscription key.

    Returns:
        Tuple of (media_type, saved_path_or_list, caption) if successful, otherwise None.
    """
    target_path = Path(output_path)
    endpoint = "https://instagram-downloader-download-instagram-videos-stories.p.rapidapi.com/index"
    headers = {
        "x-rapidapi-key": api_key,
        "x-rapidapi-host": "instagram-downloader-download-instagram-videos-stories.p.rapidapi.com",
    }
    params = {"url": url}
    try:
        response = requests.get(endpoint, headers=headers, params=params, timeout=15)
        if response.status_code == 200:
            data = response.json()
            cdn_url = data.get("media") or data.get("url") or data.get("download_url")
            caption = data.get("caption") or data.get("title") or ""
            if cdn_url and _is_valid_video_link(cdn_url):
                log.debug(f"[rapidapi] Got CDN link: {cdn_url[:60]}...")
                video_response = requests.get(cdn_url, stream=True, timeout=30)
                if video_response.status_code == 200:
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    with target_path.open("wb") as f:
                        for chunk in video_response.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                    if target_path.exists() and target_path.stat().st_size > 0:
                        return "video", str(target_path), caption
            elif cdn_url:
                log.debug("[rapidapi] Link points to image, saving as jpg.")
                target_path.parent.mkdir(parents=True, exist_ok=True)
                img_path = target_path.parent / f"{target_path.stem}_1.jpg"
                img_resp = requests.get(cdn_url, stream=True, timeout=30)
                if img_resp.status_code == 200:
                    with img_path.open("wb") as f:
                        for chunk in img_resp.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                    if img_path.exists() and img_path.stat().st_size > 0:
                        return "images", [str(img_path)], caption
    except Exception as e:
        log.warning(f"[rapidapi] Helper failed for {url}: {e}")
    return None


def _download_yt_dlp(
    url: str, output_path: Union[str, Path], cookies_path: Optional[Union[str, Path]] = None
) -> Optional[Tuple[str, str]]:
    """Downloads video using local yt-dlp library.

    Args:
        url: Source URL to ingest.
        output_path: Target filesystem path for downloaded video.
        cookies_path: Optional path to netscape cookie file.

    Returns:
        Tuple of (output_path_str, caption) if successful, otherwise None.
    """
    out_path = Path(output_path)
    opts = {
        "format": "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
        "outtmpl": str(out_path),
        "merge_output_format": "mp4",
        "quiet": True,
        "no_warnings": True,
    }

    if cookies_path:
        cookie_p = Path(cookies_path)
        if cookie_p.exists():
            opts["cookiefile"] = str(cookie_p)

    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
            caption = info.get("description", "") or info.get("title", "")

            if not info.get("formats"):
                return None
            ydl.download([url])
            if out_path.exists():
                return str(out_path), caption
    except Exception as e:
        log.warning(f"yt-dlp download failed for {url}: {e}")
        return None
    return None


def _download_instaloader(url: str) -> Optional[Tuple[List[str], str]]:
    """Downloads Instagram carousels/images using Instaloader.

    Args:
        url: Source Instagram post URL.

    Returns:
        Tuple of (sorted_image_path_list, caption) if successful, otherwise None.
    """
    match = re.search(r"/(?:p|reels|reel)/([^/?#&]+)", url)
    if not match:
        return None

    shortcode = match.group(1)
    temp_dir = Path("temp_images")
    loader = instaloader.Instaloader(
        download_pictures=True,
        download_videos=False,  # We use yt-dlp for videos
        download_video_thumbnails=False,
        download_geotags=False,
        download_comments=False,
        save_metadata=False,
        compress_json=False,
        dirname_pattern=str(temp_dir),
    )

    try:
        if temp_dir.exists():
            shutil.rmtree(temp_dir)

        post = instaloader.Post.from_shortcode(loader.context, shortcode)
        caption = post.caption or ""
        loader.download_post(post, target=str(temp_dir))

        images = [
            str(p)
            for p in temp_dir.iterdir()
            if p.suffix.lower() in {".jpg", ".png", ".webp"}
        ]
        if images:
            return sorted(images), caption
        return None
    except Exception as e:
        log.warning(f"Instaloader failed for {url}: {e}")
        return None


def download_video(
    url: str, output_path: Union[str, Path], cookies_path: Optional[Union[str, Path]] = None
) -> str:
    """Downloads video content specifically, raising an error if images are returned.

    Args:
        url: Source URL to ingest.
        output_path: Target filesystem path for downloaded video.
        cookies_path: Optional path to netscape cookie file.

    Returns:
        Path string to the downloaded video file.
    """
    res_type, res_data, _ = download_content(url, output_path, cookies_path)
    if res_type == "video":
        return str(res_data)
    raise RuntimeError(f"Download found images instead of video for {url}.")


