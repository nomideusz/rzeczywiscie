<script>
  export let projects = []
  export let stats = {}
  export let live

  let newTaskTitles = {}
  let expandedProjects = {}

  // Initialize expanded state for all projects
  $: {
    projects.forEach(project => {
      if (expandedProjects[project.id] === undefined) {
        expandedProjects[project.id] = true
      }
    })
  }

  function toggleTask(taskId) {
    live.pushEvent("toggle_task", { task_id: taskId })
  }

  function updateTaskStatus(taskId, status) {
    live.pushEvent("update_task_status", { task_id: taskId, status: status })
  }

  function createTask(projectId) {
    const title = newTaskTitles[projectId]
    if (title && title.trim()) {
      live.pushEvent("create_task", { project_id: projectId, title: title.trim() })
      newTaskTitles[projectId] = ""
    }
  }

  function toggleProject(projectId) {
    expandedProjects[projectId] = !expandedProjects[projectId]
  }

  function getStatusColor(status) {
    const colors = {
      'not_started': 'badge-ghost',
      'in_progress': 'badge-info',
      'blocked': 'badge-warning',
      'completed': 'badge-success'
    }
    return colors[status] || 'badge-ghost'
  }

  function getStatusText(status) {
    const text = {
      'not_started': 'Not Started',
      'in_progress': 'In Progress',
      'blocked': 'Blocked',
      'completed': 'Completed'
    }
    return text[status] || status
  }
</script>

<div class="space-y-6">
  {#each projects as project (project.id)}
    <div class="card bg-base-100 shadow-xl border-l-4" style="border-left-color: {project.color}">
      <div class="card-body">
        <!-- Project Header -->
        <div class="flex justify-between items-start mb-4">
          <div class="flex-1">
            <h2 class="card-title text-2xl mb-2">
              <button
                class="flex items-center gap-2 hover:opacity-80"
                onclick={() => toggleProject(project.id)}
              >
                <span class="transform transition-transform" class:rotate-90={expandedProjects[project.id]}>
                  ▶
                </span>
                {project.title}
              </button>
            </h2>
            {#if project.description}
              <p class="text-sm text-gray-600">{project.description}</p>
            {/if}
          </div>

          <div class="text-right">
            <div class="text-3xl font-bold" style="color: {project.color}">
              {project.progress_pct}%
            </div>
            <div class="text-xs text-gray-500">
              {project.tasks.filter(t => t.status === 'completed').length}/{project.tasks.length} tasks
            </div>
          </div>
        </div>

        <!-- Progress Bar -->
        <div class="w-full bg-base-300 rounded-full h-2 mb-4">
          <div
            class="h-2 rounded-full transition-all duration-300"
            style="width: {project.progress_pct}%; background-color: {project.color}"
          ></div>
        </div>

        {#if expandedProjects[project.id]}
          <!-- Tasks List -->
          <div class="space-y-2 mb-4">
            {#if project.tasks.length === 0}
              <p class="text-gray-500 italic text-center py-4">No tasks yet. Add one below!</p>
            {:else}
              {#each project.tasks as task (task.id)}
                <div class="flex items-start gap-3 p-3 bg-base-200 rounded-lg hover:bg-base-300 transition-colors">
                  <!-- Checkbox -->
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary mt-1"
                    checked={task.status === 'completed'}
                    onchange={() => toggleTask(task.id)}
                  />

                  <!-- Task Content -->
                  <div class="flex-1">
                    <div class="font-medium" class:line-through={task.status === 'completed'}>
                      {task.title}
                    </div>
                    {#if task.description}
                      <div class="text-sm text-gray-600 mt-1">{task.description}</div>
                    {/if}
                    {#if task.phase}
                      <div class="text-xs text-gray-500 mt-1">Phase: {task.phase}</div>
                    {/if}
                  </div>

                  <!-- Status Badge & Actions -->
                  <div class="flex items-center gap-2">
                    <select
                      class="select select-sm {getStatusColor(task.status)}"
                      value={task.status}
                      onchange={(e) => updateTaskStatus(task.id, e.target.value)}
                    >
                      <option value="not_started">Not Started</option>
                      <option value="in_progress">In Progress</option>
                      <option value="blocked">Blocked</option>
                      <option value="completed">Completed</option>
                    </select>
                  </div>
                </div>
              {/each}
            {/if}
          </div>

          <!-- Add Task Form -->
          <div class="flex gap-2">
            <input
              type="text"
              placeholder="Add a new task..."
              class="input input-bordered flex-1"
              bind:value={newTaskTitles[project.id]}
              onkeydown={(e) => {
                if (e.key === 'Enter') {
                  createTask(project.id)
                }
              }}
            />
            <button
              class="btn btn-primary"
              onclick={() => createTask(project.id)}
              disabled={!newTaskTitles[project.id] || !newTaskTitles[project.id].trim()}
            >
              Add Task
            </button>
          </div>

          <!-- Target Date -->
          {#if project.target_date}
            <div class="text-sm text-gray-500 mt-4">
              🎯 Target: {new Date(project.target_date).toLocaleDateString()}
            </div>
          {/if}
        {/if}
      </div>
    </div>
  {/each}

  {#if projects.length === 0}
    <div class="alert alert-info">
      <span>No projects yet. Let's get you started with your life transition plan!</span>
    </div>
  {/if}
</div>

<style>
  .rotate-90 {
    transform: rotate(90deg);
  }
</style>
