class CrybotWeb {
  constructor() {
    this.ws = null;
    this.sessionId = null;
    this.currentSection = 'chat';
    this.currentTab = localStorage.getItem('crybotTab') || 'chat-tab';
    this.currentTelegramChat = null;
    this.pushToTalkActive = false;

    this.init();
  }

  init() {
    this.setupNavigation();
    this.setupTabs();
    this.setupForms();
    this.connectWebSocket();
    this.loadConfiguration();
    this.loadLogs();

    // Restore the saved tab
    this.showTab(this.currentTab);
  }

  setupNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    navItems.forEach(item => {
      item.addEventListener('click', (e) => {
        e.preventDefault();
        const section = item.dataset.section;
        this.showSection(section);
      });
    });
  }

  showSection(section) {
    // Update nav items
    document.querySelectorAll('.nav-item').forEach(item => {
      item.classList.remove('active');
      if (item.dataset.section === section) {
        item.classList.add('active');
      }
    });

    // Update sections
    document.querySelectorAll('.section').forEach(sec => {
      sec.classList.remove('active');
    });
    document.getElementById(`section-${section}`).classList.add('active');

    this.currentSection = section;
  }

  setupTabs() {
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const tabId = tab.dataset.tab;
        this.showTab(tabId);
      });
    });
  }

  showTab(tabId) {
    // Update tab buttons
    document.querySelectorAll('.tab').forEach(tab => {
      tab.classList.remove('active');
      if (tab.dataset.tab === tabId) {
        tab.classList.add('active');
      }
    });

    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
      content.classList.remove('active');
    });
    document.getElementById(tabId).classList.add('active');

    this.currentTab = tabId;

    // Save to localStorage
    localStorage.setItem('crybotTab', tabId);

    // Load content based on tab
    if (tabId === 'telegram-tab') {
      this.loadTelegramConversations();
    } else if (tabId === 'voice-tab') {
      this.loadVoiceConversation();
    }
  }

  setupForms() {
    // Chat form
    document.getElementById('chat-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendChatMessage('chat');
    });

    // Telegram form
    document.getElementById('telegram-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendChatMessage('telegram');
    });

    // Voice form
    document.getElementById('voice-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendChatMessage('voice');
    });

    // Config form
    document.getElementById('config-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.saveConfiguration();
    });

    // Telegram back button
    document.getElementById('telegram-back').addEventListener('click', () => {
      this.showTelegramList();
    });

    // Chat back button
    const chatBackBtn = document.getElementById('chat-back');
    if (chatBackBtn) {
      chatBackBtn.addEventListener('click', () => {
        this.showChatList();
      });
    }

    // New chat button
    const newChatBtn = document.getElementById('new-chat-btn');
    if (newChatBtn) {
      newChatBtn.addEventListener('click', () => {
        this.createNewChat();
      });
    }

    // Push-to-talk button
    const pttBtn = document.querySelector('.push-to-talk-btn');
    if (pttBtn) {
      // Mouse events
      pttBtn.addEventListener('mousedown', (e) => {
        e.preventDefault();
        this.activatePushToTalk();
      });
      pttBtn.addEventListener('mouseup', () => {
        this.deactivatePushToTalk();
      });
      pttBtn.addEventListener('mouseleave', () => {
        if (this.pushToTalkActive) {
          this.deactivatePushToTalk();
        }
      });

      // Touch events for mobile
      pttBtn.addEventListener('touchstart', (e) => {
        e.preventDefault();
        this.activatePushToTalk();
      });
      pttBtn.addEventListener('touchend', (e) => {
        e.preventDefault();
        this.deactivatePushToTalk();
      });
    }
  }

  connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws/chat`;

    this.ws = new WebSocket(wsUrl);

    this.ws.onopen = () => {
      console.log('Connected to Crybot');

      // Request chat history when connected
      const savedSessionId = localStorage.getItem('crybotChatSession') || null;
      this.ws.send(JSON.stringify({
        type: 'history_request',
        session_id: savedSessionId || '',
      }));
    };

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.handleWebSocketMessage(data);
    };

    this.ws.onclose = () => {
      console.log('Disconnected from Crybot');
      setTimeout(() => this.connectWebSocket(), 3000);
    };

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
  }

  handleWebSocketMessage(data) {
    switch (data.type) {
      case 'connected':
        this.sessionId = data.session_id;
        // Save to localStorage if not already saved
        if (!localStorage.getItem('crybotChatSession')) {
          localStorage.setItem('crybotChatSession', data.session_id);
        }
        // Load sessions list after connecting
        this.loadSessionsList();
        break;
      case 'history':
        this.loadHistory(data.messages, data.session_id);
        // Show chat view when history is loaded
        this.showChatView();
        // Refresh sessions list to show all available
        this.loadSessionsList();
        break;
      case 'session_switched':
        this.sessionId = data.session_id;
        localStorage.setItem('crybotChatSession', data.session_id);
        // Clear the chat container and show it's a new session
        document.getElementById('chat-messages').innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">New conversation started</p>';
        // Show chat view
        this.showChatView();
        // Refresh sessions list
        this.loadSessionsList();
        break;
      case 'status':
        if (data.status === 'processing') {
          this.showTypingIndicator(this.getCurrentContainer());
        }
        break;
      case 'response':
        this.hideTypingIndicator(this.getCurrentContainer());
        this.addMessage(data.content, 'assistant', this.getCurrentContainer());
        break;
      case 'telegram_message':
        // New message arrived via Telegram
        this.handleExternalMessage('telegram', data);
        break;
      case 'voice_message':
        // New message arrived via Voice
        this.handleExternalMessage('voice', data);
        break;
      case 'error':
        this.hideTypingIndicator(this.getCurrentContainer());
        this.addMessage(`Error: ${data.message}`, 'system', this.getCurrentContainer());
        break;
    }
  }

  loadHistory(messages, sessionId) {
    this.sessionId = sessionId;
    localStorage.setItem('crybotChatSession', sessionId);

    const container = document.getElementById('chat-messages');
    container.innerHTML = '';

    if (!messages || messages.length === 0) {
      container.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No messages yet. Start a conversation!</p>';
      return;
    }

    messages.forEach((msg) => {
      if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
        this.addMessage(msg.content, msg.role, 'chat-messages');
      }
    });
  }

  showTypingIndicator(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // Remove existing indicator if any
    this.hideTypingIndicator(containerId);

    const indicator = document.createElement('div');
    indicator.className = 'message assistant typing-indicator';
    indicator.id = `${containerId}-typing`;
    indicator.innerHTML = `
      <div class="message-avatar">C</div>
      <div class="message-content">
        <div class="typing-dots">
          <span></span>
          <span></span>
          <span></span>
        </div>
      </div>
    `;
    container.appendChild(indicator);
    container.scrollTop = container.scrollHeight;
  }

  hideTypingIndicator(containerId) {
    const indicator = document.getElementById(`${containerId}-typing`);
    if (indicator) {
      indicator.remove();
    }
  }

  handleExternalMessage(source, data) {
    console.log(`[${source.toUpperCase()}] Received external message:`, data);
    console.log(`Current tab: ${this.currentTab}`);

    // If we're currently viewing the corresponding tab, refresh the content
    if (this.currentTab === `${source}-tab`) {
      console.log('On matching tab, checking view state...');

      if (source === 'telegram') {
        // If we're viewing the conversation list, refresh it
        const listContainer = document.getElementById('telegram-list');
        const chatView = document.getElementById('telegram-chat-view');

        console.log('List container hidden?', listContainer?.classList.contains('hidden'));
        console.log('Chat view hidden?', chatView?.classList.contains('hidden'));
        console.log('Current telegram chat:', this.currentTelegramChat);

        if (listContainer && !listContainer.classList.contains('hidden')) {
          console.log('Refreshing telegram list...');
          this.loadTelegramConversations();
        } else if (chatView && !chatView.classList.contains('hidden') && this.currentTelegramChat) {
          console.log('Refreshing telegram chat:', this.currentTelegramChat);
          this.openTelegramChat(this.currentTelegramChat);
        } else {
          console.log('Not viewing a telegram list or chat');
        }
      } else if (source === 'voice') {
        // Reload voice conversation
        this.loadVoiceConversation();
      }
    } else {
      console.log(`Not on ${source} tab (on ${this.currentTab}), skipping refresh`);
    }
  }

  getCurrentContainer() {
    switch (this.currentTab) {
      case 'chat-tab':
        return 'chat-messages';
      case 'telegram-tab':
        return 'telegram-messages';
      case 'voice-tab':
        return 'voice-messages';
      default:
        return 'chat-messages';
    }
  }

  sendChatMessage(context) {
    const formId = context === 'chat' ? 'chat-form' :
                    context === 'telegram' ? 'telegram-form' : 'voice-form';
    const form = document.getElementById(formId);
    const input = form.querySelector('.message-input');
    const content = input.value.trim();

    if (!content) return;

    // For telegram, send to the telegram-specific endpoint
    if (context === 'telegram' && this.currentTelegramChat) {
      this.sendToTelegram(content);
      return;
    }

    this.addMessage(content, 'user', this.getCurrentContainer());
    input.value = '';

    // Send via WebSocket
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'message',
        session_id: this.sessionId || '',
        content: content,
      }));
    } else {
      // Fallback to REST API
      this.sendViaAPI(content);
    }
  }

  async sendToTelegram(content) {
    const form = document.getElementById('telegram-form');
    const input = form.querySelector('.message-input');

    this.addMessage(content, 'user', 'telegram-messages');
    input.value = '';

    // Show typing indicator
    this.showTypingIndicator('telegram-messages');

    try {
      const response = await fetch(`/api/telegram/conversations/${encodeURIComponent(this.currentTelegramChat)}/message`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content }),
      });

      const data = await response.json();
      if (data.error) {
        this.hideTypingIndicator('telegram-messages');
        this.addMessage(`Error: ${data.error}`, 'system', 'telegram-messages');
      }
      // Note: We don't manually add the assistant message here because
      // the WebSocket broadcast will handle displaying the response
      // The broadcast will also hide the typing indicator
    } catch (error) {
      this.hideTypingIndicator('telegram-messages');
      console.error('Failed to send to telegram:', error);
      this.addMessage('Failed to send message to Telegram', 'system', 'telegram-messages');
    }
  }

  async sendViaAPI(content) {
    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: this.sessionId || '',
          content: content,
        }),
      });

      const data = await response.json();
      if (data.content) {
        this.addMessage(data.content, 'assistant', this.getCurrentContainer());
      }
    } catch (error) {
      this.addMessage('Failed to send message', 'system', this.getCurrentContainer());
    }
  }

  addMessage(content, role, containerId) {
    console.log('addMessage called:', { containerId, role, contentLength: content?.length });
    const container = document.getElementById(containerId);
    console.log('Container element:', container);
    if (!container) {
      console.error('Container not found:', containerId);
      return;
    }

    const messageEl = document.createElement('div');
    messageEl.className = `message ${role}`;

    const avatar = role === 'user' ? 'U' : role === 'assistant' ? 'C' : '!';
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    // Parse markdown for assistant messages, escape HTML for user messages
    let renderedContent;
    if (role === 'assistant') {
      // Parse markdown for assistant messages
      renderedContent = typeof marked !== 'undefined' ? marked.parse(content) : this.escapeHtml(content);
    } else {
      renderedContent = this.escapeHtml(content);
    }

    messageEl.innerHTML = `
      <div class="message-avatar">${avatar}</div>
      <div class="message-content">
        <div class="message-bubble">${renderedContent}</div>
        <div class="message-time">${time}</div>
      </div>
    `;

    console.log('Appending message element to container');
    container.appendChild(messageEl);
    console.log('Message appended, container now has', container.children.length, 'children');
    container.scrollTop = container.scrollHeight;
  }

  async loadTelegramConversations() {
    const listContainer = document.getElementById('telegram-list');
    listContainer.innerHTML = '<p style="color: #666;">Loading conversations...</p>';

    try {
      const response = await fetch('/api/telegram/conversations');
      const data = await response.json();

      if (!data.conversations || data.conversations.length === 0) {
        listContainer.innerHTML = '<p style="color: #666;">No conversations found.</p>';
        return;
      }

      listContainer.innerHTML = '';
      data.conversations.forEach(conv => {
        const item = document.createElement('div');
        item.className = 'telegram-conversation-item';
        item.innerHTML = `
          <div class="telegram-conversation-title">${this.escapeHtml(conv.title || 'Unknown')}</div>
          <div class="telegram-conversation-preview">${this.escapeHtml(conv.preview || 'No messages')}</div>
          <div class="telegram-conversation-time">${conv.time || ''}</div>
        `;
        item.addEventListener('click', () => this.openTelegramChat(conv.id));
        listContainer.appendChild(item);
      });
    } catch (error) {
      listContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load conversations.</p>';
    }
  }

  async openTelegramChat(chatId) {
    console.log('openTelegramChat called with:', chatId);
    this.currentTelegramChat = chatId;

    const listContainer = document.getElementById('telegram-list');
    const chatView = document.getElementById('telegram-chat-view');

    console.log('Before toggle - list hidden?', listContainer?.classList.contains('hidden'));
    console.log('Before toggle - chatView hidden?', chatView?.classList.contains('hidden'));

    listContainer?.classList.add('hidden');
    chatView?.classList.remove('hidden');

    console.log('After toggle - list hidden?', listContainer?.classList.contains('hidden'));
    console.log('After toggle - chatView hidden?', chatView?.classList.contains('hidden'));

    // Load messages for this chat
    const messagesContainer = document.getElementById('telegram-messages');
    console.log('Messages container:', messagesContainer);
    console.log('Is container in DOM?', document.body.contains(messagesContainer));
    messagesContainer.innerHTML = '<p style="color: #666;">Loading messages...</p>';

    try {
      const url = `/api/telegram/conversations/${encodeURIComponent(chatId)}?_=${Date.now()}`;
      console.log('Fetching from:', url);
      const response = await fetch(url, { cache: 'no-store' });
      const data = await response.json();
      console.log('Response data:', data);

      messagesContainer.innerHTML = '';

      if (!data.messages || data.messages.length === 0) {
        console.log('No messages found in response');
        messagesContainer.innerHTML = '<p style="color: #666;">No messages yet.</p>';
        return;
      }

      console.log('Processing', data.messages.length, 'messages');
      // Display messages (filter out system messages)
      data.messages.forEach((msg, index) => {
        console.log(`Message ${index}:`, msg);
        // Only show user and assistant messages, skip system/tool messages
        if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
          console.log('Adding message with role:', msg.role);
          this.addMessage(msg.content, msg.role, 'telegram-messages');
        }
      });
      console.log('Finished adding messages, container children:', messagesContainer.children.length);

      // Force reflow and scroll to bottom
      messagesContainer.offsetHeight; // Force reflow
      messagesContainer.scrollTop = messagesContainer.scrollHeight;

      // Debug: check if messages are actually visible
      console.log('Container styles:', {
        display: getComputedStyle(messagesContainer).display,
        visibility: getComputedStyle(messagesContainer).visibility,
        height: getComputedStyle(messagesContainer).height,
        overflow: getComputedStyle(messagesContainer).overflow,
        clientHeight: messagesContainer.clientHeight,
        scrollHeight: messagesContainer.scrollHeight,
      });

      // Log first few message elements
      for (let i = 0; i < Math.min(3, messagesContainer.children.length); i++) {
        const child = messagesContainer.children[i];
        console.log(`Child ${i}:`, {
          tagName: child.tagName,
          className: child.className,
          display: getComputedStyle(child).display,
          offsetHeight: child.offsetHeight,
          innerHTML: child.innerHTML.substring(0, 100),
        });
      }
    } catch (error) {
      console.error('Failed to load messages:', error);
      messagesContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load messages.</p>';
    }
  }

  showTelegramList() {
    this.currentTelegramChat = null;
    document.getElementById('telegram-list').classList.remove('hidden');
    document.getElementById('telegram-chat-view').classList.add('hidden');
  }

  async loadVoiceConversation() {
    const messagesContainer = document.getElementById('voice-messages');
    messagesContainer.innerHTML = '<p style="color: #666;">Loading voice conversation...</p>';

    try {
      const response = await fetch('/api/voice/conversation/current');
      const data = await response.json();

      messagesContainer.innerHTML = '';

      if (!data.messages || data.messages.length === 0) {
        messagesContainer.innerHTML = '<p style="color: #666;">No voice conversations yet. Use voice mode to start chatting.</p>';
        return;
      }

      // Display messages (filter out system messages)
      data.messages.forEach(msg => {
        // Only show user and assistant messages, skip system/tool messages
        if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
          this.addMessage(msg.content, msg.role, 'voice-messages');
        }
      });
    } catch (error) {
      console.error('Failed to load voice conversation:', error);
      messagesContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load voice conversation.</p>';
    }
  }

  async loadConfiguration() {
    try {
      const response = await fetch('/api/config');
      const config = await response.json();

      // Web
      document.getElementById('web-enabled').checked = config.web?.enabled || false;
      document.getElementById('web-host').value = config.web?.host || '127.0.0.1';
      document.getElementById('web-port').value = config.web?.port || 3000;
      document.getElementById('web-auth-token').value = '';

      // Agents
      document.getElementById('agent-model').value = config.agents?.defaults?.model || 'glm-4.7-flash';
      document.getElementById('agent-temperature').value = config.agents?.defaults?.temperature || 0.7;
      document.getElementById('agent-max-tokens').value = config.agents?.defaults?.max_tokens || 4096;

      // Providers
      document.getElementById('provider-zhipu-key').value = '';
      document.getElementById('provider-openai-key').value = '';
      document.getElementById('provider-anthropic-key').value = '';

      // Channels - Telegram
      document.getElementById('telegram-enabled').checked = config.channels?.telegram?.enabled || false;
      document.getElementById('telegram-token').value = '';
      document.getElementById('telegram-allow-from').value = (config.channels?.telegram?.allow_from || []).join(', ');
    } catch (error) {
      console.error('Failed to load configuration:', error);
    }
  }

  async saveConfiguration() {
    const config = {
      web: {
        enabled: document.getElementById('web-enabled').checked,
        host: document.getElementById('web-host').value,
        port: parseInt(document.getElementById('web-port').value),
        auth_token: document.getElementById('web-auth-token').value,
      },
      agents: {
        defaults: {
          model: document.getElementById('agent-model').value,
          temperature: parseFloat(document.getElementById('agent-temperature').value),
          max_tokens: parseInt(document.getElementById('agent-max-tokens').value),
        },
      },
      providers: {
        zhipu: { api_key: document.getElementById('provider-zhipu-key').value },
        openai: { api_key: document.getElementById('provider-openai-key').value },
        anthropic: { api_key: document.getElementById('provider-anthropic-key').value },
      },
      channels: {
        telegram: {
          enabled: document.getElementById('telegram-enabled').checked,
          token: document.getElementById('telegram-token').value,
          allow_from: document.getElementById('telegram-allow-from').value.split(',').map(s => s.trim()).filter(s => s),
        },
      },
    };

    try {
      const response = await fetch('/api/config', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config),
      });

      if (response.ok) {
        alert('Configuration saved successfully!');
      } else {
        const error = await response.json();
        alert(`Failed to save: ${error.error || 'Unknown error'}`);
      }
    } catch (error) {
      alert('Failed to save configuration');
    }
  }

  loadLogs() {
    const logsContainer = document.getElementById('logs-container');
    logsContainer.innerHTML = `
      <div class="log-entry">
        <span class="log-time">[${new Date().toISOString()}]</span>
        <span class="log-level-info">[INFO]</span>
        <span class="log-message">Crybot Web UI initialized</span>
      </div>
    `;

    // TODO: Implement real-time log streaming via WebSocket or polling
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  async activatePushToTalk() {
    if (this.pushToTalkActive) return;

    try {
      const response = await fetch('/api/voice/push-to-talk', {
        method: 'POST',
      });

      if (response.ok) {
        this.pushToTalkActive = true;
        const pttBtn = document.querySelector('.push-to-talk-btn');
        if (pttBtn) {
          pttBtn.textContent = 'Listening...';
          pttBtn.style.backgroundColor = '#27ae60';
        }
      }
    } catch (error) {
      console.error('Failed to activate push-to-talk:', error);
    }
  }

  async deactivatePushToTalk() {
    if (!this.pushToTalkActive) return;

    try {
      const response = await fetch('/api/voice/push-to-talk', {
        method: 'DELETE',
      });

      if (response.ok) {
        this.pushToTalkActive = false;
        const pttBtn = document.querySelector('.push-to-talk-btn');
        if (pttBtn) {
          pttBtn.textContent = 'Push to talk';
          pttBtn.style.backgroundColor = '';
        }
      }
    } catch (error) {
      console.error('Failed to deactivate push-to-talk:', error);
    }
  }

  async loadSessionsList() {
    try {
      const response = await fetch('/api/sessions');
      const data = await response.json();

      const listContainer = document.getElementById('chat-list');
      if (!listContainer) return;

      listContainer.innerHTML = '';

      if (!data.sessions || data.sessions.length === 0) {
        listContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No conversations yet. Start chatting!</p>';
        return;
      }

      // Filter to show web_ and repl_ sessions, plus "repl" and "cli" (not telegram or voice)
      const chatSessions = data.sessions.filter(s =>
        s.startsWith('web_') ||
        s.startsWith('repl_') ||
        s === 'repl' ||
        s === 'cli'
      );

      if (chatSessions.length === 0) {
        listContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No conversations yet. Start chatting!</p>';
        return;
      }

      // Check each session for messages and filter out empty ones
      const sessionsWithMessages = [];

      for (const sessionId of chatSessions) {
        try {
          const sessionResponse = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}`);
          const sessionData = await sessionResponse.json();

          // Filter out messages that have actual content (not just system/tool messages)
          const userMessages = sessionData.messages.filter(m =>
            m.content && (m.role === 'user' || m.role === 'assistant')
          );

          if (userMessages.length > 0) {
            sessionsWithMessages.push({
              id: sessionId,
              lastMessage: userMessages[userMessages.length - 1].content,
              messageCount: userMessages.length,
            });
          }
        } catch (e) {
          console.error('Failed to load session:', sessionId, e);
        }
      }

      if (sessionsWithMessages.length === 0) {
        listContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No conversations yet. Start chatting!</p>';
        return;
      }

      // Sort sessions by ID (newest first based on timestamp prefix)
      sessionsWithMessages.sort((a, b) => b.id.localeCompare(a.id));

      sessionsWithMessages.forEach(session => {
        const item = document.createElement('div');
        item.className = 'chat-conversation-item';
        item.dataset.sessionId = session.id;

        // Get session info
        const sessionInfo = this.formatSessionInfo(session.id, session.lastMessage);
        const isCurrent = session.id === this.sessionId;

        item.innerHTML = `
          <div class="chat-conversation-content">
            <div class="chat-conversation-title">${this.escapeHtml(sessionInfo.title)}</div>
            <div class="chat-conversation-preview">${this.escapeHtml(sessionInfo.preview)}</div>
            <div class="chat-conversation-time">${sessionInfo.time}</div>
          </div>
          <button class="chat-conversation-delete" data-session="${session.id}" title="Delete conversation">×</button>
        `;

        if (isCurrent) {
          item.classList.add('active');
        }

        // Click on item opens the chat
        item.addEventListener('click', (e) => {
          // Don't open if clicking the delete button
          if (!e.target.classList.contains('chat-conversation-delete')) {
            this.openChatSession(session.id);
          }
        });

        // Delete button click handler
        const deleteBtn = item.querySelector('.chat-conversation-delete');
        deleteBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          this.deleteSession(session.id);
        });

        listContainer.appendChild(item);
      });
    } catch (error) {
      console.error('Failed to load sessions:', error);
    }
  }

  formatSessionInfo(sessionId, lastMessage) {
    // Parse session ID and format for display
    let title = 'Conversation';
    let preview = lastMessage || 'No messages';
    let time = '';

    if (sessionId.startsWith('web_')) {
      title = 'Web Chat';
      // Extract timestamp from session ID
      const timestamp = sessionId.substring(4);
      if (timestamp.length >= 8) {
        time = this.formatSessionTime(timestamp.substring(0, 8));
      }
    } else if (sessionId.startsWith('repl_')) {
      title = 'REPL Session';
      const timestamp = sessionId.substring(5);
      if (timestamp.length >= 8) {
        time = this.formatSessionTime(timestamp.substring(0, 8));
      }
    } else if (sessionId === 'repl') {
      title = 'REPL Session';
    } else if (sessionId === 'cli') {
      title = 'CLI Command';
    }

    // Truncate preview if too long
    if (preview && preview.length > 50) {
      preview = preview.substring(0, 50) + '...';
    }

    return { title, preview, time };
  }

  formatSessionTime(hexTime) {
    try {
      // Convert hex timestamp to readable time
      const timestamp = parseInt(hexTime, 16);
      const date = new Date(timestamp * 1000);
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

      if (diffDays === 0) {
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      } else if (diffDays === 1) {
        return 'Yesterday';
      } else if (diffDays < 7) {
        return date.toLocaleDateString([], { weekday: 'short' });
      } else {
        return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
      }
    } catch {
      return '';
    }
  }

  async openChatSession(sessionId) {
    // Show chat view
    this.showChatView();

    // Load messages for this session
    try {
      const response = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}`);
      const data = await response.json();

      // Update current session
      this.sessionId = sessionId;
      localStorage.setItem('crybotChatSession', sessionId);

      const container = document.getElementById('chat-messages');
      container.innerHTML = '';

      if (!data.messages || data.messages.length === 0) {
        container.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No messages yet. Start a conversation!</p>';
        return;
      }

      // Display messages (filter out system messages)
      data.messages.forEach(msg => {
        if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
          this.addMessage(msg.content, msg.role, 'chat-messages');
        }
      });

      // Refresh list to update active state
      this.loadSessionsList();
    } catch (error) {
      console.error('Failed to load session:', error);
    }
  }

  showChatList() {
    const listContainer = document.getElementById('chat-list');
    const chatView = document.getElementById('chat-view');

    listContainer?.classList.remove('hidden');
    chatView?.classList.add('hidden');

    // Refresh the list to show latest state
    this.loadSessionsList();
  }

  async deleteSession(sessionId) {
    if (!confirm('Are you sure you want to delete this conversation?')) {
      return;
    }

    try {
      const response = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}`, {
        method: 'DELETE',
      });

      if (response.ok) {
        // If we deleted the current session, go back to list
        if (sessionId === this.sessionId) {
          this.showChatList();
          this.sessionId = null;
          localStorage.removeItem('crybotChatSession');
        }
        // Refresh the list
        this.loadSessionsList();
      } else {
        alert('Failed to delete conversation');
      }
    } catch (error) {
      console.error('Failed to delete session:', error);
      alert('Failed to delete conversation');
    }
  }

  showChatView() {
    const listContainer = document.getElementById('chat-list');
    const chatView = document.getElementById('chat-view');

    listContainer?.classList.add('hidden');
    chatView?.classList.remove('hidden');
  }

  switchSession(sessionId) {
    if (!sessionId) return;

    // Show the chat view when switching to a session
    this.showChatView();

    // Switch to the selected session via WebSocket
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'session_switch',
        session_id: sessionId,
      }));
    }
  }

  createNewChat() {
    // Show the chat view for new chat
    this.showChatView();

    // Create a new session by sending empty session_id
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'session_switch',
        session_id: '', // Empty means create new
      }));
    }
  }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  new CrybotWeb();
});
