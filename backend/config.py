"""
Command Center - Configuration
Loads all environment variables and provides typed settings.
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Google / Gmail
    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = "http://localhost:8766/auth/google/callback"
    gmail_account_1: str = ""
    gmail_account_2: str = ""
    gmail_account_3: str = ""
    google_cloud_project_id: str = ""
    google_pubsub_topic: str = ""
    google_pubsub_subscription: str = ""

    # Microsoft / Outlook
    ms_client_id: str = ""
    ms_client_secret: str = ""
    ms_tenant_id: str = ""
    ms_redirect_uri: str = "http://localhost:8766/auth/microsoft/callback"
    outlook_account: str = ""

    # Slack
    slack_workspace_1_bot_token: str = ""
    slack_workspace_1_app_token: str = ""
    slack_workspace_1_name: str = "Workspace 1"
    slack_workspace_2_bot_token: str = ""
    slack_workspace_2_app_token: str = ""
    slack_workspace_2_name: str = "Workspace 2"

    # Asana
    asana_access_token: str = ""
    asana_default_workspace_gid: str = ""
    asana_default_project_gid: str = ""

    # Plane
    plane_api_url: str = "https://app.plane.so/api/v1"
    plane_api_key: str = ""
    plane_workspace_slug: str = ""
    plane_default_project_id: str = ""

    # App
    backend_port: int = 8766
    database_url: str = "sqlite+aiosqlite:///./command_center.db"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

    @property
    def gmail_accounts(self) -> list[str]:
        return [a for a in [self.gmail_account_1, self.gmail_account_2, self.gmail_account_3] if a]

    @property
    def slack_workspaces(self) -> list[dict]:
        workspaces = []
        if self.slack_workspace_1_bot_token:
            workspaces.append(
                {
                    "name": self.slack_workspace_1_name,
                    "bot_token": self.slack_workspace_1_bot_token,
                    "app_token": self.slack_workspace_1_app_token,
                }
            )
        if self.slack_workspace_2_bot_token:
            workspaces.append(
                {
                    "name": self.slack_workspace_2_name,
                    "bot_token": self.slack_workspace_2_bot_token,
                    "app_token": self.slack_workspace_2_app_token,
                }
            )
        return workspaces


settings = Settings()
