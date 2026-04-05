function [feature_table, sim_data] = extract_features_batch(sim_data, params)
% EXTRACT_FEATURES_BATCH Extract r_CP and a_FP features for all positions in sim_data.
if nargin < 2
    params = struct();
end
if ~isstruct(sim_data)
    error('[extract_features_batch] sim_data must be a struct.');
end

required_fields = {'CIR_rx1', 'CIR_rx2', 't_axis'};
for idx = 1:numel(required_fields)
    if ~isfield(sim_data, required_fields{idx})
        error('[extract_features_batch] sim_data.%s is required.', required_fields{idx});
    end
end

cir_rx1 = sim_data.CIR_rx1;
cir_rx2 = sim_data.CIR_rx2;
if size(cir_rx1, 1) ~= size(cir_rx2, 1) || size(cir_rx1, 2) ~= size(cir_rx2, 2)
    error('[extract_features_batch] CIR_rx1 and CIR_rx2 must have same shape.');
end

n_pos = size(cir_rx1, 1);
t_axis = sim_data.t_axis(:);

r_cp = nan(n_pos, 1);
a_fp = nan(n_pos, 1);
valid_flag = true(n_pos, 1);
fp_idx_rhcp = nan(n_pos, 1);
fp_idx_lhcp = nan(n_pos, 1);

for idx_pos = 1:n_pos
    cir1 = cir_rx1(idx_pos, :).';
    cir2 = cir_rx2(idx_pos, :).';

    params_local = params;
    params_local.t_axis = t_axis;

    [r_cp_val, rcp_info] = extract_rcp(cir1, cir2, params_local);
    [a_fp_val, ~] = extract_afp(cir1, cir2, t_axis, params_local);

    r_cp(idx_pos) = r_cp_val;
    a_fp(idx_pos) = a_fp_val;
    fp_idx_rhcp(idx_pos) = double(rcp_info.fp_idx_RHCP);
    fp_idx_lhcp(idx_pos) = double(rcp_info.fp_idx_LHCP);

    if ~isfinite(r_cp_val) || ~isfinite(a_fp_val)
        valid_flag(idx_pos) = false;
    end

    if mod(idx_pos, 100) == 0 || idx_pos == n_pos
        fprintf('[extract_features_batch] %d/%d positions processed (%.1f%%)\n', ...
            idx_pos, n_pos, 100 * idx_pos / n_pos);
    end
end

r_cp_clip = get_param(params, 'r_CP_clip', 1e4);
r_cp(r_cp > r_cp_clip) = r_cp_clip;

if isfield(sim_data, 'labels') && numel(sim_data.labels) == n_pos
    labels = logical(sim_data.labels(:));
else
    labels = true(n_pos, 1);
    warning('[extract_features_batch] sim_data.labels missing; labels defaulted to true (LoS).');
end

if isfield(sim_data, 'pos_id') && numel(sim_data.pos_id) == n_pos
    pos_id = uint32(sim_data.pos_id(:));
else
    pos_id = uint32((1:n_pos)');
end

if isfield(sim_data, 'RSS_rx1') && numel(sim_data.RSS_rx1) == n_pos
    rss_rhcp = double(sim_data.RSS_rx1(:));
else
    rss_rhcp = nan(n_pos, 1);
end

if isfield(sim_data, 'RSS_rx2') && numel(sim_data.RSS_rx2) == n_pos
    rss_lhcp = double(sim_data.RSS_rx2(:));
else
    rss_lhcp = nan(n_pos, 1);
end

feature_table = table( ...
    pos_id, ...
    r_cp, ...
    a_fp, ...
    labels, ...
    valid_flag, ...
    fp_idx_rhcp, ...
    fp_idx_lhcp, ...
    rss_rhcp, ...
    rss_lhcp, ...
    'VariableNames', {'pos_id', 'r_CP', 'a_FP', 'label', 'valid_flag', 'fp_idx_RHCP', 'fp_idx_LHCP', 'RSS_RHCP', 'RSS_LHCP'});
end
