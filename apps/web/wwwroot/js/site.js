/**
 * PPT Generator - Test Interface JavaScript
 */

document.addEventListener('DOMContentLoaded', function () {
    // Elements
    const submitForm = document.getElementById('submitForm');
    const jsonInput = document.getElementById('jsonInput');
    const submitBtn = document.getElementById('submitBtn');
    const formatBtn = document.getElementById('formatBtn');
    const validateBtn = document.getElementById('validateBtn');
    const clearBtn = document.getElementById('clearBtn');
    const loadSampleBtn = document.getElementById('loadSampleBtn');
    const samplesMenu = document.getElementById('samplesMenu');
    const statusCard = document.getElementById('statusCard');
    const refreshJobsBtn = document.getElementById('refreshJobsBtn');
    const jobsList = document.getElementById('jobsList');

    let currentJobId = null;
    let pollingInterval = null;

    // Load samples on page load
    loadSamples();
    loadJobs();

    // Form submission
    if (submitForm) {
        submitForm.addEventListener('submit', async function (e) {
            e.preventDefault();

            const jsonContent = jsonInput.value.trim();
            if (!jsonContent) {
                alert('Please enter JSON content');
                return;
            }

            // Validate JSON
            try {
                JSON.parse(jsonContent);
            } catch (e) {
                alert('Invalid JSON: ' + e.message);
                return;
            }

            // Disable button and show loading
            submitBtn.disabled = true;
            submitBtn.querySelector('.btn-text').style.display = 'none';
            submitBtn.querySelector('.btn-loader').style.display = 'inline';

            try {
                const formData = new FormData();
                formData.append('jsonContent', jsonContent);

                const response = await fetch('/Home/Submit', {
                    method: 'POST',
                    body: formData
                });

                const result = await response.json();

                if (result.jobId) {
                    currentJobId = result.jobId;
                    showStatusCard(result);
                    startPolling(result.jobId);
                    loadJobs();
                } else if (result.error) {
                    alert('Error: ' + result.error);
                }
            } catch (error) {
                alert('Error submitting job: ' + error.message);
            } finally {
                submitBtn.disabled = false;
                submitBtn.querySelector('.btn-text').style.display = 'inline';
                submitBtn.querySelector('.btn-loader').style.display = 'none';
            }
        });
    }

    // Format JSON
    if (formatBtn) {
        formatBtn.addEventListener('click', function () {
            try {
                const json = JSON.parse(jsonInput.value);
                jsonInput.value = JSON.stringify(json, null, 2);
            } catch (e) {
                alert('Cannot format: Invalid JSON');
            }
        });
    }

    // Validate JSON
    if (validateBtn) {
        validateBtn.addEventListener('click', function () {
            try {
                JSON.parse(jsonInput.value);
                alert('Valid JSON!');
            } catch (e) {
                alert('Invalid JSON: ' + e.message);
            }
        });
    }

    // Clear input
    if (clearBtn) {
        clearBtn.addEventListener('click', function () {
            jsonInput.value = '';
        });
    }

    // Load sample dropdown
    if (loadSampleBtn) {
        loadSampleBtn.addEventListener('click', function (e) {
            e.stopPropagation();
            samplesMenu.classList.toggle('show');
        });
    }

    // Close dropdown on outside click
    document.addEventListener('click', function (e) {
        if (samplesMenu && !e.target.closest('.samples-dropdown')) {
            samplesMenu.classList.remove('show');
        }
    });

    // Refresh jobs list
    if (refreshJobsBtn) {
        refreshJobsBtn.addEventListener('click', loadJobs);
    }

    // Load samples from server
    async function loadSamples() {
        if (!samplesMenu) return;

        try {
            const response = await fetch('/Home/Samples');
            const samples = await response.json();

            samplesMenu.innerHTML = samples.map(sample => `
                <div class="dropdown-item" data-content="${escapeHtml(sample.content || '')}">
                    <div class="title">${escapeHtml(sample.title)}</div>
                    <div class="meta">${escapeHtml(sample.filename)} - ${escapeHtml(sample.sourceType)}</div>
                </div>
            `).join('');

            // Add click handlers
            samplesMenu.querySelectorAll('.dropdown-item').forEach(item => {
                item.addEventListener('click', function () {
                    const content = this.getAttribute('data-content');
                    if (content && jsonInput) {
                        jsonInput.value = decodeHtml(content);
                        samplesMenu.classList.remove('show');
                    }
                });
            });
        } catch (error) {
            console.error('Error loading samples:', error);
        }
    }

    // Load jobs list
    async function loadJobs() {
        if (!jobsList) return;

        try {
            const response = await fetch('/Home/Jobs');
            const jobs = await response.json();

            if (jobs.length === 0) {
                jobsList.innerHTML = '<p class="empty-state">No jobs submitted yet</p>';
                return;
            }

            jobsList.innerHTML = jobs.slice(0, 10).map(job => {
                const jobId = job.jobId || job.id;
                const title = getJobTitle(job);
                const created = job.created_at || job.createdAt;
                return `
                <div class="job-item" data-job-id="${jobId}">
                    <div class="job-info">
                        <div class="job-title">${jobId.substring(0, 8)}...</div>
                        <div class="job-meta">${title}</div>
                    </div>
                    <span class="status-badge status-${job.status}">${capitalizeFirst(job.status)}</span>
                </div>
            `}).join('');

            // Add click handlers
            jobsList.querySelectorAll('.job-item').forEach(item => {
                item.addEventListener('click', function () {
                    const jobId = this.getAttribute('data-job-id');
                    currentJobId = jobId;
                    startPolling(jobId);
                });
            });
        } catch (error) {
            console.error('Error loading jobs:', error);
        }
    }

    // Show status card
    function showStatusCard(status) {
        if (!statusCard) return;

        statusCard.style.display = 'block';
        document.getElementById('jobId').textContent = status.jobId || currentJobId;
        updateStatusCard(status);
    }

    // Update status card
    function updateStatusCard(status) {
        const progressFill = document.getElementById('progressFill');
        const progressText = document.getElementById('progressText');
        const statusValue = document.getElementById('statusValue');
        const currentStep = document.getElementById('currentStep');
        const downloadSection = document.getElementById('downloadSection');
        const errorSection = document.getElementById('errorSection');
        const downloadLink = document.getElementById('downloadLink');
        const errorMessage = document.getElementById('errorMessage');

        const progress = status.progress || 0;
        progressFill.style.width = progress + '%';
        progressText.textContent = progress + '%';

        statusValue.textContent = status.status || 'Unknown';
        statusValue.className = 'value status-badge status-' + (status.status || 'unknown');

        currentStep.textContent = formatStepName(status.stage || status.currentStep) || '-';

        if (status.status === 'completed' && (status.downloadUrl || status.outputUrl)) {
            downloadSection.style.display = 'block';
            downloadLink.href = status.downloadUrl || status.outputUrl;
            errorSection.style.display = 'none';
            stopPolling();
        } else if (status.status === 'error') {
            errorSection.style.display = 'block';
            errorMessage.textContent = status.error || 'An error occurred';
            downloadSection.style.display = 'none';
            stopPolling();
        } else {
            downloadSection.style.display = 'none';
            errorSection.style.display = 'none';
        }
    }

    // Start polling for status
    function startPolling(jobId) {
        stopPolling();

        // Initial fetch
        fetchStatus(jobId);

        // Poll every 2 seconds
        pollingInterval = setInterval(() => fetchStatus(jobId), 2000);
    }

    // Stop polling
    function stopPolling() {
        if (pollingInterval) {
            clearInterval(pollingInterval);
            pollingInterval = null;
        }
    }

    // Fetch status
    async function fetchStatus(jobId) {
        try {
            const response = await fetch('/Home/Status?id=' + encodeURIComponent(jobId));
            const status = await response.json();

            if (response.ok) {
                showStatusCard(status);
                loadJobs();
            }
        } catch (error) {
            console.error('Error fetching status:', error);
        }
    }

    // Format step name
    function formatStepName(step) {
        if (!step) return null;
        return step.split('_').map(word =>
            word.charAt(0).toUpperCase() + word.slice(1)
        ).join(' ');
    }

    // Format date
    function formatDate(dateString) {
        if (!dateString) return 'Unknown';
        try {
            const date = new Date(dateString);
            return date.toLocaleString();
        } catch {
            return dateString;
        }
    }

    // Escape HTML for attributes
    function escapeHtml(text) {
        if (!text) return '';
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    // Decode HTML entities
    function decodeHtml(text) {
        const doc = new DOMParser().parseFromString(text, 'text/html');
        return doc.documentElement.textContent;
    }

    // Get job title from payload or default
    function getJobTitle(job) {
        if (job.payload && job.payload.presentationContext && job.payload.presentationContext.title) {
            return job.payload.presentationContext.title;
        }
        return formatDate(job.created_at || job.createdAt);
    }

    // Capitalize first letter
    function capitalizeFirst(str) {
        if (!str) return 'Unknown';
        return str.charAt(0).toUpperCase() + str.slice(1);
    }
});
