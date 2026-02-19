"""
Google OAuth 2.0 helpers for Gmail integration.

Handles the full OAuth flow:
1. Build consent URL → user visits in browser
2. Exchange authorization code for tokens
3. Store/load tokens from the database
"""

from datetime import datetime

from google_auth_oauthlib.flow import Flow
from sqlalchemy import select

from config import settings
from models.database import TokenStore, async_session

# Gmail scopes needed for reading + replying
GMAIL_SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
]


def _make_client_config() -> dict:
    """Build the client config dict expected by google_auth_oauthlib."""
    return {
        "web": {
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [settings.google_redirect_uri],
        }
    }


def build_auth_url(email: str) -> str:
    """Generate the Google OAuth consent URL.

    The email is passed as `state` so the callback knows which account
    to associate the tokens with. `login_hint` pre-fills the Google
    account picker with the expected address.
    """
    flow = Flow.from_client_config(
        _make_client_config(),
        scopes=GMAIL_SCOPES,
        redirect_uri=settings.google_redirect_uri,
    )
    auth_url, _ = flow.authorization_url(
        access_type="offline",
        prompt="consent",
        state=email,
        login_hint=email,
    )
    return auth_url


def exchange_code(code: str) -> dict:
    """Exchange an authorization code for access + refresh tokens."""
    flow = Flow.from_client_config(
        _make_client_config(),
        scopes=GMAIL_SCOPES,
        redirect_uri=settings.google_redirect_uri,
    )
    flow.fetch_token(code=code)
    creds = flow.credentials
    return {
        "access_token": creds.token,
        "refresh_token": creds.refresh_token,
        "expires_at": creds.expiry.isoformat() if creds.expiry else None,
    }


async def save_tokens(email: str, tokens: dict) -> None:
    """Persist OAuth tokens to the database."""
    token_id = f"gmail:{email}"
    async with async_session() as session:
        existing = await session.get(TokenStore, token_id)
        if existing:
            existing.access_token = tokens["access_token"]
            existing.refresh_token = tokens.get("refresh_token") or existing.refresh_token
            if tokens.get("expires_at"):
                existing.expires_at = datetime.fromisoformat(tokens["expires_at"])
        else:
            record = TokenStore(
                id=token_id,
                service="gmail",
                account=email,
                access_token=tokens["access_token"],
                refresh_token=tokens.get("refresh_token", ""),
                expires_at=(
                    datetime.fromisoformat(tokens["expires_at"])
                    if tokens.get("expires_at")
                    else None
                ),
            )
            session.add(record)
        await session.commit()


async def load_tokens(email: str) -> dict | None:
    """Load stored OAuth tokens for a Gmail account.

    Returns a dict with access_token and refresh_token, or None if
    no tokens are stored for the given email.
    """
    token_id = f"gmail:{email}"
    async with async_session() as session:
        result = await session.execute(select(TokenStore).where(TokenStore.id == token_id))
        record = result.scalar_one_or_none()
        if not record:
            return None
        return {
            "access_token": record.access_token,
            "refresh_token": record.refresh_token,
        }
