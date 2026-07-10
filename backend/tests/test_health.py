"""Harness smoke test: the app answers /health on an isolated DB."""


async def test_health(client) -> None:
    """The app boots and reports ok against a temp database."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
