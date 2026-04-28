import pytest


@pytest.mark.asyncio
async def test_metrics_endpoint_returns_prometheus_format(client):
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert "text/plain" in resp.headers["content-type"]
    # Prometheus text format always starts with "# HELP" or "# TYPE"
    assert b"# HELP" in resp.content or b"# TYPE" in resp.content
