function [r_CP, rcp_info] = extract_rcp(cir_rx1, cir_rx2, params)
% EXTRACT_RCP Compute first-path power ratio r_CP from two polarization CIR vectors.
if nargin < 3
    params = struct();
end

cir_rx1 = cir_rx1(:);
cir_rx2 = cir_rx2(:);
if numel(cir_rx1) ~= numel(cir_rx2)
    error('[extract_rcp] cir_rx1 and cir_rx2 must have same length.');
end

r_cp_clip = get_param(params, 'r_CP_clip', 1e4);
if ~isfinite(r_cp_clip) || r_cp_clip <= 0
    error('[extract_rcp] params.r_CP_clip must be positive finite scalar.');
end

min_power_dbm = get_param(params, 'min_power_dbm', -inf);
if isfinite(min_power_dbm)
    min_power_linear = 10.^((double(min_power_dbm) - 30) / 10);
else
    min_power_linear = 0;
end

power_mode = upper(string(get_param(params, 'rcp_power_mode', 'PEAK')));
if ~(power_mode == "PEAK" || power_mode == "WINDOW")
    error('[extract_rcp] params.rcp_power_mode must be ''PEAK'' or ''WINDOW''.');
end
window_ns = get_param(params, 'rcp_window_ns', get_param(params, 'T_w', 2.0));
if ~isfinite(window_ns) || window_ns < 0
    error('[extract_rcp] params.rcp_window_ns must be non-negative finite scalar.');
end

t_axis = get_param(params, 't_axis', []);
if ~isempty(t_axis)
    t_axis = double(t_axis(:));
    if numel(t_axis) ~= numel(cir_rx1)
        error('[extract_rcp] params.t_axis length must match CIR length.');
    end
end

% FP reference policy:
%   INDEPENDENT (legacy): RHCP/LHCP each detect its own FP index.
%   RHCP: use RHCP FP index for both RHCP and LHCP powers.
fp_reference = upper(string(get_param(params, 'fp_reference', 'INDEPENDENT')));
switch fp_reference
    case "INDEPENDENT"
        [fp_idx_rx1, ~] = detect_first_path(abs(cir_rx1), params);
        [fp_idx_rx2, ~] = detect_first_path(abs(cir_rx2), params);
    case "RHCP"
        [fp_idx_rx1, ~] = detect_first_path(abs(cir_rx1), params);
        fp_idx_rx2 = fp_idx_rx1;
    otherwise
        error('[extract_rcp] Unknown params.fp_reference: %s', fp_reference);
end
[p_rx1, win_range_rx1] = extract_fp_power(cir_rx1, fp_idx_rx1, t_axis, power_mode, window_ns);
[p_rx2, win_range_rx2] = extract_fp_power(cir_rx2, fp_idx_rx2, t_axis, power_mode, window_ns);

if p_rx1 <= min_power_linear
    p_rx1 = 0;
end
if p_rx2 <= min_power_linear
    p_rx2 = 0;
end

if p_rx1 == 0 && p_rx2 == 0
    r_CP = NaN;
    flag = "both_zero";
elseif p_rx2 == 0 && p_rx1 > 0
    r_CP = r_cp_clip;
    flag = "lhcp_zero";
elseif p_rx1 == 0 && p_rx2 > 0
    r_CP = 0;
    flag = "rhcp_zero";
else
    r_CP = p_rx1 / p_rx2;
    if r_CP > r_cp_clip
        r_CP = r_cp_clip;
        flag = "clipped";
    else
        flag = "ok";
    end
end

rcp_info = struct();
rcp_info.P_rx1 = p_rx1;
rcp_info.P_rx2 = p_rx2;
rcp_info.fp_idx_RHCP = fp_idx_rx1;
rcp_info.fp_idx_LHCP = fp_idx_rx2;
rcp_info.flag = flag;
rcp_info.fp_reference = fp_reference;
rcp_info.power_mode = power_mode;
rcp_info.window_ns = window_ns;
rcp_info.win_range_ns_rx1 = win_range_rx1;
rcp_info.win_range_ns_rx2 = win_range_rx2;
end

function [power_val, win_range_ns] = extract_fp_power(cir_vec, fp_idx, t_axis, power_mode, window_ns)
power_val = 0;
win_range_ns = [NaN, NaN];

if isnan(fp_idx)
    return;
end

fp_idx = double(fp_idx);
if fp_idx < 1 || fp_idx > numel(cir_vec)
    return;
end

if power_mode == "PEAK" || isempty(t_axis)
    power_val = abs(cir_vec(fp_idx)).^2;
    return;
end

t_fp = t_axis(fp_idx);
t_start = t_fp - window_ns;
t_end = t_fp + window_ns;
mask = (t_axis >= t_start) & (t_axis <= t_end);
if ~any(mask)
    power_val = abs(cir_vec(fp_idx)).^2;
else
    power_val = sum(abs(cir_vec(mask)).^2);
end
win_range_ns = [t_start, t_end];
end
