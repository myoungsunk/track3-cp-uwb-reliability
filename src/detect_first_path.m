function [fp_idx, fp_info] = detect_first_path(cir_abs, params)
% DETECT_FIRST_PATH Detect leading-edge first path index from CIR magnitude.
if nargin < 2
    params = struct();
end

cir_abs = double(cir_abs(:));
n_tap = numel(cir_abs);

fp_info = struct( ...
    'peak_idx', uint32(0), ...
    'peak_val', NaN, ...
    'threshold', NaN, ...
    'search_range', [uint32(1), uint32(max(1, n_tap))], ...
    'found', false);

if n_tap == 0
    fp_idx = NaN;
    return;
end

fp_threshold_ratio = get_param(params, 'fp_threshold_ratio', 0.2);
if ~isfinite(fp_threshold_ratio) || fp_threshold_ratio < 0
    error('[detect_first_path] params.fp_threshold_ratio must be non-negative finite scalar.');
end

search_start = 1;
search_end = n_tap;
search_window_ns = get_param(params, 'fp_search_window_ns', []);
t_axis_ns = get_param(params, 't_axis', []);

if ~isempty(search_window_ns)
    if numel(search_window_ns) ~= 2 || any(~isfinite(search_window_ns))
        error('[detect_first_path] params.fp_search_window_ns must be [start_ns, end_ns].');
    end
    if isempty(t_axis_ns)
        error('[detect_first_path] params.t_axis is required when fp_search_window_ns is set.');
    end

    t_axis_ns = double(t_axis_ns(:));
    if numel(t_axis_ns) ~= n_tap
        error('[detect_first_path] params.t_axis length must match cir_abs length.');
    end

    t_start_ns = min(search_window_ns);
    t_end_ns = max(search_window_ns);

    idx_start = find(t_axis_ns >= t_start_ns, 1, 'first');
    idx_end = find(t_axis_ns <= t_end_ns, 1, 'last');

    if ~isempty(idx_start)
        search_start = idx_start;
    end
    if ~isempty(idx_end)
        search_end = idx_end;
    end

    search_start = max(1, min(n_tap, search_start));
    search_end = max(1, min(n_tap, search_end));
    if search_end < search_start
        tmp = search_start;
        search_start = search_end;
        search_end = tmp;
    end
end

fp_info.search_range = [uint32(search_start), uint32(search_end)];

cir_search = cir_abs(search_start:search_end);
[peak_val, peak_rel_idx] = max(cir_search);
peak_idx = peak_rel_idx + search_start - 1;
threshold = fp_threshold_ratio * peak_val;

fp_info.peak_idx = uint32(peak_idx);
fp_info.peak_val = peak_val;
fp_info.threshold = threshold;

if ~isfinite(peak_val) || peak_val <= 0
    fp_idx = NaN;
    return;
end

candidate_rel = find(cir_search >= threshold, 1, 'first');
if isempty(candidate_rel)
    fp_idx = NaN;
    return;
end

fp_idx = uint32(candidate_rel + search_start - 1);
fp_info.found = true;
end
