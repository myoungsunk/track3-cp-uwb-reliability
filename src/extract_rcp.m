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

[fp_idx_rx1, ~] = detect_first_path(abs(cir_rx1), params);
[fp_idx_rx2, ~] = detect_first_path(abs(cir_rx2), params);

if isnan(fp_idx_rx1)
    p_rx1 = 0;
else
    p_rx1 = abs(cir_rx1(fp_idx_rx1)).^2;
end
if isnan(fp_idx_rx2)
    p_rx2 = 0;
else
    p_rx2 = abs(cir_rx2(fp_idx_rx2)).^2;
end

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
end
