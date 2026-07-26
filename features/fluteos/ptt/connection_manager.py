"""Persistent WebSocket connection manager for Deepgram.

Maintains a single WebSocket connection using KeepAlive messages.
Handles reconnection, idle timeout, and state transitions.
"""

import json
import threading
import time
from enum import Enum

import websocket

from .config import (
    IDLE_TIMEOUT,
    KEEPALIVE_INTERVAL,
    MAX_RECONNECT_ATTEMPTS,
    WS_CONNECT_TIMEOUT,
    stt_auth_header,
    stt_ws_url,
)


class ConnectionState(Enum):
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    STREAMING = "streaming"


class ConnectionManager:
    """Manages persistent WebSocket connection to Deepgram.

    States:
    - DISCONNECTED: No connection
    - CONNECTING: WebSocket handshake in progress
    - CONNECTED: Connected, sending KeepAlive every 5 seconds
    - STREAMING: Audio streaming active, KeepAlive paused

    The connection stays open between recordings. KeepAlive messages
    prevent Deepgram from closing the connection during idle time.
    """

    def __init__(self, stt=None, api_key=None):
        # The STT backend is per-mode configuration, so it is passed in rather
        # than imported: switching to a mode with a different endpoint, model,
        # language or key reconnects (see set_backend).
        self.stt = stt
        self.api_key = api_key
        self.ws = None
        self.state = ConnectionState.DISCONNECTED
        self._state_lock = threading.Lock()
        self._ws_thread = None
        self._keepalive_thread = None
        self._should_stop = threading.Event()
        self._connected_event = threading.Event()
        self._reconnect_count = 0
        self._last_activity_time = time.time()

        # Callbacks
        self.on_connected = None  # Called when connection established
        self.on_disconnected = None  # Called when connection lost
        self.on_message = None  # Called for incoming messages
        self.on_error = None  # Called on errors

    def _set_state(self, new_state):
        with self._state_lock:
            old_state = self.state
            self.state = new_state
            print(f"Connection state: {old_state.value} -> {new_state.value}", flush=True)

            # Write state to file for waybar widget
            self._update_waybar_status(new_state)

    def _update_waybar_status(self, state):
        """Write connection state to file and signal waybar to refresh."""
        import subprocess
        from pathlib import Path

        state_file = Path.home() / ".cache" / "ptt" / "connection"
        try:
            state_file.parent.mkdir(parents=True, exist_ok=True)
            state_file.write_text(state.value)
        except Exception as e:
            print(f"Failed to write connection state: {e}", flush=True)

        # Signal waybar to update
        try:
            subprocess.run(["pkill", "-SIGRTMIN+11", "waybar"], check=False)
        except Exception:
            pass

    def set_backend(self, stt, api_key):
        """Point the manager at a (possibly different) STT backend.

        Called on every recording start with the current mode's backend. When
        endpoint/model/language/key are unchanged this is a no-op and the warm
        connection is reused; when they differ the old connection is closed so
        the next connect() speaks to the right service with the right key.
        """
        if stt == self.stt and api_key == self.api_key:
            return

        if self.state != ConnectionState.DISCONNECTED:
            print("STT backend changed; reconnecting", flush=True)
            self.disconnect()

        self.stt = stt
        self.api_key = api_key

    def connect(self):
        """Establish the WebSocket connection to the STT service.

        Non-blocking. Connection happens in background thread.
        """
        if self.stt is None or not self.api_key:
            print("No STT backend/key configured; not connecting", flush=True)
            return

        if self.state != ConnectionState.DISCONNECTED:
            print("Already connected or connecting", flush=True)
            return

        self._should_stop.clear()
        self._connected_event.clear()
        self._set_state(ConnectionState.CONNECTING)
        self._reconnect_count = 0

        self._start_connection()

    def _start_connection(self):
        """Start WebSocket connection in background thread."""
        self.ws = websocket.WebSocketApp(
            stt_ws_url(self.stt),
            header=stt_auth_header(self.stt, self.api_key),
            on_open=self._on_open,
            on_message=self._on_message,
            on_error=self._on_error,
            on_close=self._on_close,
        )

        self._ws_thread = threading.Thread(target=self._run_ws, daemon=True)
        self._ws_thread.start()

    def _run_ws(self):
        """Run WebSocket event loop."""
        try:
            self.ws.run_forever()
        except Exception as e:
            print(f"WebSocket run error: {e}", flush=True)

    def _on_open(self, ws):
        """Handle WebSocket connection established."""
        print("WebSocket connected to Deepgram", flush=True)
        self._set_state(ConnectionState.CONNECTED)
        self._connected_event.set()
        self._reconnect_count = 0
        self._last_activity_time = time.time()

        # Start KeepAlive loop
        self._start_keepalive()

        if self.on_connected:
            self.on_connected()

    def _on_message(self, ws, message):
        """Handle incoming message from Deepgram."""
        self._last_activity_time = time.time()
        if self.on_message:
            self.on_message(message)

    def _on_error(self, ws, error):
        """Handle WebSocket error."""
        print(f"WebSocket error: {error}", flush=True)
        if self.on_error:
            self.on_error(error)

    def _on_close(self, ws, close_status_code, close_msg):
        """Handle WebSocket connection closed."""
        print(f"WebSocket closed: {close_status_code} {close_msg}", flush=True)

        was_connected = self.state in (ConnectionState.CONNECTED, ConnectionState.STREAMING)
        self._set_state(ConnectionState.DISCONNECTED)
        self._connected_event.clear()

        if self.on_disconnected:
            self.on_disconnected()

        # Attempt reconnect if not intentionally stopped
        if was_connected and not self._should_stop.is_set():
            self._attempt_reconnect()

    def _start_keepalive(self):
        """Start KeepAlive thread."""
        if self._keepalive_thread and self._keepalive_thread.is_alive():
            return

        self._keepalive_thread = threading.Thread(target=self._keepalive_loop, daemon=True)
        self._keepalive_thread.start()

    def _keepalive_loop(self):
        """Send KeepAlive messages while connected and not streaming."""
        while not self._should_stop.is_set():
            time.sleep(KEEPALIVE_INTERVAL)

            if self._should_stop.is_set():
                break

            with self._state_lock:
                current_state = self.state

            # Only send KeepAlive when CONNECTED (not STREAMING)
            if current_state == ConnectionState.CONNECTED:
                # Check idle timeout
                idle_time = time.time() - self._last_activity_time
                if idle_time > IDLE_TIMEOUT:
                    print(f"Idle timeout ({IDLE_TIMEOUT}s), closing connection", flush=True)
                    self._close_connection()
                    break

                # Send KeepAlive
                try:
                    if self.ws and self.ws.sock:
                        self.ws.send(json.dumps({"type": "KeepAlive"}))
                        print("KeepAlive sent", flush=True)
                except Exception as e:
                    print(f"KeepAlive send error: {e}", flush=True)

            elif current_state == ConnectionState.DISCONNECTED:
                break

    def _attempt_reconnect(self):
        """Attempt to reconnect after connection loss."""
        if self._should_stop.is_set():
            return

        self._reconnect_count += 1
        if self._reconnect_count > MAX_RECONNECT_ATTEMPTS:
            print(f"Max reconnect attempts ({MAX_RECONNECT_ATTEMPTS}) exceeded", flush=True)
            return

        print(f"Reconnecting (attempt {self._reconnect_count}/{MAX_RECONNECT_ATTEMPTS})...", flush=True)
        time.sleep(1.0)  # Brief delay before reconnect

        if not self._should_stop.is_set():
            self._set_state(ConnectionState.CONNECTING)
            self._start_connection()

    def _close_connection(self):
        """Close WebSocket connection gracefully."""
        self._should_stop.set()
        if self.ws:
            try:
                self.ws.close()
            except Exception as e:
                print(f"Close error: {e}", flush=True)

    def start_streaming(self):
        """Signal that audio streaming is starting.

        Pauses KeepAlive messages (not needed during streaming).
        """
        if self.state == ConnectionState.CONNECTED:
            self._set_state(ConnectionState.STREAMING)
            self._last_activity_time = time.time()

    def stop_streaming(self):
        """Signal that audio streaming has stopped.

        Resumes KeepAlive messages.
        """
        if self.state == ConnectionState.STREAMING:
            self._set_state(ConnectionState.CONNECTED)
            self._last_activity_time = time.time()

    def send_control(self, message: dict) -> bool:
        """Send a control message (JSON) to Deepgram.

        Used for messages like Finalize/CloseStream. Works in both
        CONNECTED and STREAMING states.

        Returns:
            True if sent successfully, False otherwise.
        """
        try:
            if self.ws and self.ws.sock:
                self.ws.send(json.dumps(message))
                return True
        except Exception as e:
            print(f"Send control error: {e}", flush=True)
        return False

    def send_audio(self, data):
        """Send audio data to Deepgram.

        Args:
            data: Raw audio bytes to send.

        Returns:
            True if sent successfully, False otherwise.
        """
        if self.state != ConnectionState.STREAMING:
            return False

        try:
            if self.ws and self.ws.sock:
                self.ws.send(data, opcode=websocket.ABNF.OPCODE_BINARY)
                return True
        except Exception as e:
            print(f"Send audio error: {e}", flush=True)
        return False

    def wait_for_connection(self, timeout=None):
        """Wait for connection to be established.

        Args:
            timeout: Maximum time to wait in seconds.

        Returns:
            True if connected, False if timeout.
        """
        timeout = timeout or WS_CONNECT_TIMEOUT
        return self._connected_event.wait(timeout=timeout)

    def is_connected(self):
        """Check if connection is ready for use."""
        return self.state in (ConnectionState.CONNECTED, ConnectionState.STREAMING)

    def is_streaming(self):
        """Check if currently streaming audio."""
        return self.state == ConnectionState.STREAMING

    def ensure_connected(self):
        """Ensure connection is established, reconnect if needed.

        Returns:
            True if connected (or connection established), False otherwise.
        """
        if self.is_connected():
            return True

        if self.state == ConnectionState.DISCONNECTED:
            self.connect()
            # connect() refuses when no backend/key is configured; don't sit in
            # wait_for_connection() for a connection that was never attempted.
            if self.state == ConnectionState.DISCONNECTED:
                return False
            return self.wait_for_connection()

        if self.state == ConnectionState.CONNECTING:
            return self.wait_for_connection()

        return False

    def disconnect(self):
        """Disconnect and cleanup."""
        print("Disconnecting from Deepgram", flush=True)
        self._should_stop.set()

        if self.ws:
            try:
                self.ws.close()
            except Exception:
                pass

        if self._ws_thread and self._ws_thread.is_alive():
            self._ws_thread.join(timeout=2.0)

        self.ws = None
        self._set_state(ConnectionState.DISCONNECTED)
