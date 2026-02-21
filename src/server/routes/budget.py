from fastapi import APIRouter, Query

from ..services.conversation_store import conversation_store

router = APIRouter()


@router.get("")
async def get_budget_summary():
    """Get per-agent token usage totals.

    Returns aggregated input/output/cache token counts for each agent
    that has usage data in their events.
    """
    agents = conversation_store.get_budget_summary()
    return {"agents": agents}


@router.get("/{agent_id}")
async def get_agent_budget(
    agent_id: str,
    limit: int = Query(default=50, le=200),
):
    """Get token usage detail for a single agent.

    Returns totals and recent events with usage data.
    """
    return conversation_store.get_agent_budget(agent_id, limit=limit)
