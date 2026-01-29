import pytest
from fastapi.testclient import TestClient
from httpx import AsyncClient, ASGITransport
import pytest_asyncio

from src.server.main import app
from src.server.config import settings
from src.server.services.mailbox import mailbox_service


@pytest.fixture(autouse=True)
def setup_test_mailbox(tmp_path):
    """Use a temporary directory for mailbox during tests."""
    original_path = settings.mailbox_path
    original_cmux_dir = settings.cmux_dir

    # Set up temp paths
    test_cmux_dir = tmp_path / ".cmux"
    test_cmux_dir.mkdir(parents=True, exist_ok=True)
    test_mailbox = test_cmux_dir / "mailbox"

    # Override settings
    settings.cmux_dir = test_cmux_dir
    settings.mailbox_path = test_mailbox

    # Also update the mailbox service instance
    mailbox_service.mailbox_path = test_mailbox

    yield

    # Restore original paths
    settings.mailbox_path = original_path
    settings.cmux_dir = original_cmux_dir
    mailbox_service.mailbox_path = original_path


@pytest.fixture
def client():
    return TestClient(app)


@pytest_asyncio.fixture
async def async_client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
