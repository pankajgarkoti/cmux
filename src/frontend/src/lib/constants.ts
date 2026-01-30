export const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8000';
export const WS_URL = import.meta.env.VITE_WS_URL || 'ws://localhost:8000/api/agents/ws';

// WebSocket reconnection with exponential backoff
export const RECONNECT_DELAY_BASE = 1000; // Start at 1 second
export const RECONNECT_DELAY_MAX = 30000; // Cap at 30 seconds

// Legacy export for backwards compatibility
export const RECONNECT_DELAY = RECONNECT_DELAY_BASE;

export const MAX_ACTIVITIES = 500;
