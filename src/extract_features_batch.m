function [feature_table, sim_data] = extract_features_batch(sim_data, params)
% EXTRACT_FEATURES_BATCH Extract CP/UWB features for all positions in sim_data.
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

use_cp4_features = logical(get_param(params, 'use_cp4_features', true));
has_cp4_fields = all(isfield(sim_data, {'CIR_rhcp_rx1', 'CIR_lhcp_rx1', 'CIR_rhcp_rx2', 'CIR_lhcp_rx2'}));
is_cp4_mode = use_cp4_features && has_cp4_fields;

% In CP4 mode, use RHCP first-path index as shared FP reference for LHCP.
cp4_fp_reference = upper(string(get_param(params, 'cp4_fp_reference', 'RHCP')));

r_cp = nan(n_pos, 1);
a_fp = nan(n_pos, 1);
valid_flag = true(n_pos, 1);
fp_idx_rhcp = nan(n_pos, 1);
fp_idx_lhcp = nan(n_pos, 1);

r_cp_rx1 = nan(n_pos, 1);
r_cp_rx2 = nan(n_pos, 1);
a_fp_rhcp_rx1 = nan(n_pos, 1);
a_fp_lhcp_rx1 = nan(n_pos, 1);
a_fp_rhcp_rx2 = nan(n_pos, 1);
a_fp_lhcp_rx2 = nan(n_pos, 1);
fp_idx_rhcp_rx1 = nan(n_pos, 1);
fp_idx_lhcp_rx1 = nan(n_pos, 1);
fp_idx_rhcp_rx2 = nan(n_pos, 1);
fp_idx_lhcp_rx2 = nan(n_pos, 1);
fp_idx_diff_rx12 = nan(n_pos, 1);
fp_delay_diff_ns_rx12 = nan(n_pos, 1);

for idx_pos = 1:n_pos
    params_local = params;
    params_local.t_axis = t_axis;
    params_local.rcp_power_mode = upper(string(get_param(params, 'rcp_power_mode', 'WINDOW')));
    params_local.rcp_window_ns = get_param(params, 'rcp_window_ns', get_param(params, 'T_w', 2.0));

    if is_cp4_mode
        params_local.fp_reference = cp4_fp_reference;
        cir_rhcp_1 = sim_data.CIR_rhcp_rx1(idx_pos, :).';
        cir_lhcp_1 = sim_data.CIR_lhcp_rx1(idx_pos, :).';
        cir_rhcp_2 = sim_data.CIR_rhcp_rx2(idx_pos, :).';
        cir_lhcp_2 = sim_data.CIR_lhcp_rx2(idx_pos, :).';

        [r_cp_1_val, rcp_info_1] = extract_rcp(cir_rhcp_1, cir_lhcp_1, params_local);
        [r_cp_2_val, rcp_info_2] = extract_rcp(cir_rhcp_2, cir_lhcp_2, params_local);

        params_afp_rhcp = params_local;
        params_afp_rhcp.afp_cir_source = 'RHCP';
        params_afp_rhcp.fp_reference = cp4_fp_reference;
        params_afp_lhcp = params_local;
        params_afp_lhcp.afp_cir_source = 'LHCP';
        params_afp_lhcp.fp_reference = cp4_fp_reference;

        [a_fp_rhcp_1_val, ~] = extract_afp(cir_rhcp_1, cir_lhcp_1, t_axis, params_afp_rhcp);
        [a_fp_lhcp_1_val, ~] = extract_afp(cir_rhcp_1, cir_lhcp_1, t_axis, params_afp_lhcp);
        [a_fp_rhcp_2_val, ~] = extract_afp(cir_rhcp_2, cir_lhcp_2, t_axis, params_afp_rhcp);
        [a_fp_lhcp_2_val, ~] = extract_afp(cir_rhcp_2, cir_lhcp_2, t_axis, params_afp_lhcp);

        r_cp_rx1(idx_pos) = r_cp_1_val;
        r_cp_rx2(idx_pos) = r_cp_2_val;
        a_fp_rhcp_rx1(idx_pos) = a_fp_rhcp_1_val;
        a_fp_lhcp_rx1(idx_pos) = a_fp_lhcp_1_val;
        a_fp_rhcp_rx2(idx_pos) = a_fp_rhcp_2_val;
        a_fp_lhcp_rx2(idx_pos) = a_fp_lhcp_2_val;

        fp_idx_rhcp_rx1(idx_pos) = double(rcp_info_1.fp_idx_RHCP);
        fp_idx_lhcp_rx1(idx_pos) = double(rcp_info_1.fp_idx_LHCP);
        fp_idx_rhcp_rx2(idx_pos) = double(rcp_info_2.fp_idx_RHCP);
        fp_idx_lhcp_rx2(idx_pos) = double(rcp_info_2.fp_idx_LHCP);

        if isfinite(fp_idx_rhcp_rx1(idx_pos)) && isfinite(fp_idx_rhcp_rx2(idx_pos))
            fp_idx_diff_rx12(idx_pos) = abs(fp_idx_rhcp_rx1(idx_pos) - fp_idx_rhcp_rx2(idx_pos));
            idx1 = round(fp_idx_rhcp_rx1(idx_pos));
            idx2 = round(fp_idx_rhcp_rx2(idx_pos));
            if idx1 >= 1 && idx1 <= numel(t_axis) && idx2 >= 1 && idx2 <= numel(t_axis)
                fp_delay_diff_ns_rx12(idx_pos) = abs(t_axis(idx1) - t_axis(idx2));
            end
        end

        r_cp(idx_pos) = mean([r_cp_1_val, r_cp_2_val], 'omitnan');
        a_fp(idx_pos) = mean([a_fp_rhcp_1_val, a_fp_lhcp_1_val, a_fp_rhcp_2_val, a_fp_lhcp_2_val], 'omitnan');
        fp_idx_rhcp(idx_pos) = mean([fp_idx_rhcp_rx1(idx_pos), fp_idx_rhcp_rx2(idx_pos)], 'omitnan');
        fp_idx_lhcp(idx_pos) = mean([fp_idx_lhcp_rx1(idx_pos), fp_idx_lhcp_rx2(idx_pos)], 'omitnan');

        vals_6 = [r_cp_1_val, r_cp_2_val, a_fp_rhcp_1_val, a_fp_lhcp_1_val, a_fp_rhcp_2_val, a_fp_lhcp_2_val];
        if any(~isfinite(vals_6))
            valid_flag(idx_pos) = false;
        end
    else
        cir1 = cir_rx1(idx_pos, :).';
        cir2 = cir_rx2(idx_pos, :).';

        [r_cp_val, rcp_info] = extract_rcp(cir1, cir2, params_local);
        [a_fp_val, ~] = extract_afp(cir1, cir2, t_axis, params_local);

        r_cp(idx_pos) = r_cp_val;
        a_fp(idx_pos) = a_fp_val;
        fp_idx_rhcp(idx_pos) = double(rcp_info.fp_idx_RHCP);
        fp_idx_lhcp(idx_pos) = double(rcp_info.fp_idx_LHCP);

        if ~isfinite(r_cp_val) || ~isfinite(a_fp_val)
            valid_flag(idx_pos) = false;
        end
    end

    if mod(idx_pos, 100) == 0 || idx_pos == n_pos
        fprintf('[extract_features_batch] %d/%d positions processed (%.1f%%)\n', ...
            idx_pos, n_pos, 100 * idx_pos / n_pos);
    end
end

r_cp_clip = get_param(params, 'r_CP_clip', 1e4);
r_cp(r_cp > r_cp_clip) = r_cp_clip;
r_cp_rx1(r_cp_rx1 > r_cp_clip) = r_cp_clip;
r_cp_rx2(r_cp_rx2 > r_cp_clip) = r_cp_clip;

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

if is_cp4_mode
    feature_table.r_CP_rx1 = r_cp_rx1;
    feature_table.r_CP_rx2 = r_cp_rx2;
    feature_table.a_FP_RHCP_rx1 = a_fp_rhcp_rx1;
    feature_table.a_FP_LHCP_rx1 = a_fp_lhcp_rx1;
    feature_table.a_FP_RHCP_rx2 = a_fp_rhcp_rx2;
    feature_table.a_FP_LHCP_rx2 = a_fp_lhcp_rx2;
    feature_table.fp_idx_RHCP_rx1 = fp_idx_rhcp_rx1;
    feature_table.fp_idx_LHCP_rx1 = fp_idx_lhcp_rx1;
    feature_table.fp_idx_RHCP_rx2 = fp_idx_rhcp_rx2;
    feature_table.fp_idx_LHCP_rx2 = fp_idx_lhcp_rx2;
    feature_table.fp_idx_diff_rx12 = fp_idx_diff_rx12;
    feature_table.fp_delay_diff_ns_rx12 = fp_delay_diff_ns_rx12;
end
end
