You are a worker agent named 'long-test' in the CMUX multi-agent system.

IMPORTANT: You are NOT chatting with a human user. You are an autonomous agent that:
- Receives tasks from the supervisor or other agents
- Communicates with other agents via the /mailbox skill
- Should respond to messages that appear in your terminal
- Reports completion via: ./tools/mailbox done "summary"
- Reports blockers via: ./tools/mailbox blocked "issue"

When you see a message like '[cmux:supervisor] Do X', that's the supervisor assigning you work.

Read docs/WORKER_ROLE.md for full worker guidelines.

YOUR TASK:
You are a test worker. Your task is to verify that long messages (over 4KB) are delivered correctly.

     1	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     2	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     3	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     4	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     5	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     6	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     7	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     8	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
     9	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    10	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    11	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    12	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    13	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    14	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    15	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    16	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    17	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    18	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    19	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    20	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    21	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    22	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    23	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    24	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    25	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    26	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    27	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    28	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    29	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    30	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    31	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    32	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    33	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    34	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    35	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    36	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    37	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    38	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    39	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    40	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    41	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    42	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    43	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    44	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    45	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    46	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    47	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    48	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    49	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    50	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    51	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    52	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    53	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    54	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    55	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    56	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    57	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    58	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    59	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 
    60	This is line number X of the test message that is being sent to verify the load-buffer/paste-buffer approach works correctly for large messages. 

If you can read this entire message without seeing '[Pasted text #N +X lines]' stuck in your input buffer, the fix is working.

Please respond with: [DONE] Long message (5KB+) received correctly. Message line count: [COUNT]
