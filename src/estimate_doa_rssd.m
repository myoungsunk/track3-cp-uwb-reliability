function [doa_est, doa_info] = estimate_doa_rssd(rssd_measured, lut, params)
% ESTIMATE_DOA_RSSD Estimate DoA angle from measured RSSD using LUT inverse lookup.
if nargin < 3
    params = struct();
end

rssd_measured = double(rssd_measured(:));
if ~isstruct(lut) || ~isfield(lut, 'ang_axis') || ~isfield(lut, 'rssd_curve')
    error('[estimate_doa_rssd] lut must contain ang_axis and rssd_curve.');
end

ang_axis = double(lut.ang_axis(:));
rssd_curve = double(lut.rssd_curve(:));
if numel(ang_axis) ~= numel(rssd_curve)
    error('[estimate_doa_rssd] lut.ang_axis and lut.rssd_curve size mismatch.');
end

if isfield(lut, 'monotonic_range') && numel(lut.monotonic_range) == 2
    mono_min = min(lut.monotonic_range);
    mono_max = max(lut.monotonic_range);
else
    mono_min = ang_axis(1);
    mono_max = ang_axis(end);
end

mono_mask = (ang_axis >= mono_min) & (ang_axis <= mono_max);
if ~any(mono_mask)
    mono_mask = true(size(ang_axis));
end

ang_mono = ang_axis(mono_mask);
rssd_mono = rssd_curve(mono_mask);
rssd_mono_min = min(rssd_mono);
rssd_mono_max = max(rssd_mono);

candidate_tol_db = get_param(params, 'doa_candidate_tol_db', 0.1);
if ~isfinite(candidate_tol_db) || candidate_tol_db < 0
    error('[estimate_doa_rssd] params.doa_candidate_tol_db must be non-negative finite scalar.');
end

n_sample = numel(rssd_measured);
doa_est = nan(n_sample, 1);
ambiguity_flag = false(n_sample, 1);
residual = nan(n_sample, 1);
n_candidates = zeros(n_sample, 1, 'uint8');

for idx = 1:n_sample
    value = rssd_measured(idx);
    if ~isfinite(value)
        ambiguity_flag(idx) = true;
        continue;
    end

    dist_mono = abs(rssd_mono - value);
    [min_dist, min_idx] = min(dist_mono);
    doa_est(idx) = ang_mono(min_idx);
    residual(idx) = min_dist;

    dist_all = abs(rssd_curve - value);
    n_close = sum(dist_all <= candidate_tol_db);
    n_candidates(idx) = uint8(min(n_close, 255));

    outside_mono_value_range = (value < min(rssd_mono_min, rssd_mono_max)) || ...
        (value > max(rssd_mono_min, rssd_mono_max));

    if outside_mono_value_range || n_close > 1
        ambiguity_flag(idx) = true;
    end
end

doa_info = struct();
doa_info.ambiguity_flag = ambiguity_flag;
doa_info.residual = residual;
doa_info.n_candidates = n_candidates;
doa_info.monotonic_range = [mono_min, mono_max];
end
