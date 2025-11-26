c = get_config()

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
#c.ServerApp.root_dir = "/home/ubuntu/jupyter"

# --- Kernel robustness / timeouts ---
# Give slow kernels (Rust compilation) time to start.
c.ServerApp.kernel_info_timeout = 600
c.MappingKernelManager.kernel_info_timeout = 600

# Don’t kill long-running analytics sessions aggressively.
c.MappingKernelManager.cull_idle_timeout = 0        # 0 = never cull idle kernels
# Or, for some safety:
# c.MappingKernelManager.cull_idle_timeout = 43200   # 12 hours
#c.MappingKernelManager.cull_interval = 300          # check every 5 minutes

# Don’t auto-shutdown the whole server due to inactivity.
c.ServerApp.shutdown_no_activity_timeout = 0

# --- Big output / data friendliness ---
# Allow large WebSocket messages (big plots, dask dashboards, DataFrames)
c.ServerApp.max_body_size = 0   # 0 = no explicit limit

# Optional: if reverse proxying, honor X-Forwarded-Proto/Host, etc.
# c.ServerApp.trust_xheaders = True

# Logging verbosity – useful while tuning Rust kernels & timeouts.
c.ServerApp.log_level = "INFO"
