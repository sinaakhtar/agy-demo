from flask import Flask, jsonify, request, abort

app = Flask(__name__)

# In-memory database for simplicity
tasks = [
    {"id": 1, "title": "Setup GCP Project", "completed": True},
    {"id": 2, "title": "Deploy Cloud Run Service", "completed": False},
    {"id": 3, "title": "Configure Identity-Aware Proxy (IAP)", "completed": False},
]

@app.route("/tasks", methods=["GET"])
def get_tasks():
    return jsonify(tasks)

@app.route("/tasks", methods=["POST"])
def create_task():
    if not request.json or "title" not in request.json:
        abort(400)
    
    new_id = max([t["id"] for t in tasks]) + 1 if tasks else 1
    new_task = {
        "id": new_id,
        "title": request.json["title"],
        "completed": False
    }
    tasks.append(new_task)
    return jsonify(new_task), 201

@app.route("/tasks/<task_id>", methods=["DELETE"])
def delete_task(task_id):
    # BUG: task_id from URL is a string (e.g., "3"), but the task["id"] is an integer.
    # The comparison `t["id"] == task_id` will always evaluate to False.
    # This prevents deletion and returns a 404 error, which will fail the unit tests.
    task_to_delete = None
    for t in tasks:
        if t["id"] == task_id:  # Bug here! Should be int(task_id) or t["id"] == int(task_id)
            task_to_delete = t
            break
            
    if task_to_delete is None:
        abort(404, description="Task not found")
        
    tasks.remove(task_to_delete)
    return jsonify({"result": True}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
