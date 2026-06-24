import pytest
from app import app, tasks

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        # Reset tasks list before each test to ensure predictable state
        tasks.clear()
        tasks.extend([
            {"id": 1, "title": "Setup GCP Project", "completed": True},
            {"id": 2, "title": "Deploy Cloud Run Service", "completed": False},
            {"id": 3, "title": "Configure Identity-Aware Proxy (IAP)", "completed": False},
        ])
        yield client

def test_get_tasks(client):
    """Test retrieving all tasks."""
    response = client.get("/tasks")
    assert response.status_code == 200
    data = response.get_json()
    assert len(data) == 3
    assert data[0]["title"] == "Setup GCP Project"

def test_create_task(client):
    """Test creating a new task."""
    response = client.post("/tasks", json={"title": "Test Antigravity Demo"})
    assert response.status_code == 201
    data = response.get_json()
    assert data["id"] == 4
    assert data["title"] == "Test Antigravity Demo"
    assert data["completed"] is False

def test_delete_task(client):
    """Test deleting an existing task."""
    # We try to delete task with ID 3
    response = client.delete("/tasks/3")
    assert response.status_code == 200
    data = response.get_json()
    assert data["result"] is True
    
    # Verify it was actually removed from the list
    get_response = client.get("/tasks")
    assert get_response.status_code == 200
    get_data = get_response.get_json()
    assert len(get_data) == 2
    assert not any(t["id"] == 3 for t in get_data)
