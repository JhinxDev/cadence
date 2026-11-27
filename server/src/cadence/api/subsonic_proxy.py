"""Transparent streaming-safe OpenSubsonic /rest/* proxy to Navidrome."""

from collections.abc import AsyncIterator

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import Response, StreamingResponse

router = APIRouter(tags=["subsonic-proxy"])


@router.api_route("/rest/{subpath:path}", methods=["GET", "POST"])
async def proxy_subsonic(subpath: str, request: Request) -> Response:
    navidrome_url = request.app.state.settings.navidrome_url.rstrip("/")
    target = f"{navidrome_url}/rest/{subpath}"

    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in {"host", "connection", "content-length"}
    }
    body = await request.body()

    client = httpx.AsyncClient(timeout=30.0, follow_redirects=True)
    req = client.build_request(
        method=request.method,
        url=target,
        params=request.query_params,
        headers=headers,
        content=body if body else None,
    )
    upstream = await client.send(req, stream=True)

    resp_headers = {
        k: v
        for k, v in upstream.headers.items()
        if k.lower() not in {"transfer-encoding", "connection"}
    }

    async def stream_body() -> AsyncIterator[bytes]:
        try:
            async for chunk in upstream.aiter_bytes(65536):
                yield chunk
        finally:
            await upstream.aclose()
            await client.aclose()

    return StreamingResponse(
        stream_body(),
        status_code=upstream.status_code,
        headers=resp_headers,
        media_type=upstream.headers.get("content-type"),
    )
