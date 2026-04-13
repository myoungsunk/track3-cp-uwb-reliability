function [a_FP, afp_info] = extract_afp(cir_rx1, cir_rx2, t_axis, params)
% EXTRACT_AFP Compute first-path energy concentration ratio a_FP for selected CIR source.
if nargin < 4
    params = struct();
end

cir_rx1 = cir_rx1(:);
cir_rx2 = cir_rx2(:);
t_axis = double(t_axis(:));

if numel(cir_rx1) ~= numel(cir_rx2) || numel(cir_rx1) ~= numel(t_axis)
    error('[extract_afp] cir_rx1, cir_rx2, t_axis must have same length.');
end

source = upper(string(get_param(params, 'afp_cir_source', 'RHCP')));
switch source
    case "RHCP"
        cir_used = cir_rx1;
    case "LHCP"
        cir_used = cir_rx2;
    case "COMBINED"
        cir_used = (cir_rx1 + cir_rx2) / 2;
    case "POWER_SUM"
        cir_used = sqrt(abs(cir_rx1).^2 + abs(cir_rx2).^2);
    otherwise
        error('[extract_afp] Unknown params.afp_cir_source: %s', source);
end

% FP reference policy:
%   SELF/SOURCE: detect FP from selected cir_used (legacy behavior)
%   RHCP:        detect FP from cir_rx1 and reuse it for any source (requested CP policy)
%   LHCP:        detect FP from cir_rx2
fp_reference = upper(string(get_param(params, 'fp_reference', 'SELF')));
switch fp_reference
    case {"SELF", "SOURCE"}
        cir_fp_ref = cir_used;
    case "RHCP"
        cir_fp_ref = cir_rx1;
    case "LHCP"
        cir_fp_ref = cir_rx2;
    otherwise
        error('[extract_afp] Unknown params.fp_reference: %s', fp_reference);
end

params_fp = params;
params_fp.t_axis = t_axis;
[fp_idx, ~] = detect_first_path(abs(cir_fp_ref), params_fp);

t_w_ns = get_param(params, 'T_w', 2.0);
if ~isfinite(t_w_ns) || t_w_ns < 0
    error('[extract_afp] params.T_w must be non-negative finite scalar (ns).');
end

if isnan(fp_idx)
    a_FP = NaN;
    afp_info = struct('cir_used', source, 'E_fp', NaN, 'E_total', NaN, ...
        'fp_idx', NaN, 'win_range', [NaN, NaN], 'fp_reference', fp_reference);
    return;
end

t_fp_ns = t_axis(fp_idx);
win_start_ns = t_fp_ns - t_w_ns;
win_end_ns = t_fp_ns + t_w_ns;
win_mask = (t_axis >= win_start_ns) & (t_axis <= win_end_ns);

E_fp = sum(abs(cir_used(win_mask)).^2);
E_total = sum(abs(cir_used).^2);
if E_total <= 0
    a_FP = NaN;
else
    a_FP = E_fp / E_total;
    a_FP = min(max(a_FP, 0), 1);
end

afp_info = struct();
afp_info.cir_used = source;
afp_info.E_fp = E_fp;
afp_info.E_total = E_total;
afp_info.fp_idx = fp_idx;
afp_info.win_range = [win_start_ns, win_end_ns];
afp_info.fp_reference = fp_reference;
end
