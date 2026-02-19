// Command Center - Tauri Backend
// Launches the app window and spawns the Python FastAPI backend as a child process.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::process::{Child, Command};
use std::sync::Mutex;

use tauri::Manager;

struct BackendProcess(Mutex<Option<Child>>);

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .manage(BackendProcess(Mutex::new(None)))
        .setup(|app| {
            println!("Command Center starting...");

            // Resolve the backend directory (project_root/backend)
            let backend_dir = std::env::current_dir()
                .expect("Failed to get current directory")
                .join("backend");

            if !backend_dir.exists() {
                // Fallback: try relative to the executable
                let exe_dir = std::env::current_exe()
                    .ok()
                    .and_then(|p| p.parent().map(|d| d.to_path_buf()));
                if let Some(dir) = exe_dir {
                    let alt = dir.join("backend");
                    if alt.exists() {
                        println!("[Backend] Found backend at: {:?}", alt);
                    }
                }
                println!("[Backend] Warning: backend dir not found at {:?}", backend_dir);
                println!("[Backend] Start the backend manually: cd backend && uv run uvicorn main:app --port 8766");
                return Ok(());
            }

            println!("[Backend] Spawning from: {:?}", backend_dir);

            match Command::new("uv")
                .args(["run", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8766"])
                .current_dir(&backend_dir)
                .spawn()
            {
                Ok(child) => {
                    println!("[Backend] Python backend started (PID: {})", child.id());
                    let state = app.state::<BackendProcess>();
                    *state.0.lock().unwrap() = Some(child);
                }
                Err(e) => {
                    eprintln!("[Backend] Failed to spawn: {}", e);
                    eprintln!("[Backend] Make sure 'uv' is installed and in PATH");
                }
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                let child = window.state::<BackendProcess>().0.lock().unwrap().take();
                if let Some(mut child) = child {
                    println!("[Backend] Killing backend process...");
                    let _ = child.kill();
                    let _ = child.wait();
                    println!("[Backend] Backend process terminated");
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running command center");
}
