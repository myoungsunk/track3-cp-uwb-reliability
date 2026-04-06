function merged = merge_sim_data(a, b, params)
% MERGE_SIM_DATA Merge two sim_data structs row-wise with axis consistency checks.
if nargin < 3
    params = struct();
end
if ~isstruct(a) || ~isstruct(b)
    error('[merge_sim_data] inputs must be structs.');
end

validate_merge_compatibility(a, b, params);

n_existing = get_sample_count(a);
merged = a;
fields_to_stack = {'CIR_rx1', 'CIR_rx2', 'labels', 'x_coord_m', 'y_coord_m', 'RSS_rx1', 'RSS_rx2', 'pol_type', 'case_id'};
for idx = 1:numel(fields_to_stack)
    field_name = fields_to_stack{idx};
    if isfield(merged, field_name) && isfield(b, field_name)
        merged.(field_name) = [merged.(field_name); b.(field_name)]; %#ok<AGROW>
    end
end

if isfield(merged, 'pos_id') && isfield(b, 'pos_id')
    offset = max(double(merged.pos_id));
    merged.pos_id = [merged.pos_id; uint32(double(b.pos_id) + offset)];
end

if isfield(merged, 'inc_ang') && isfield(b, 'inc_ang')
    merged.inc_ang = [merged.inc_ang; b.inc_ang(:)];
elseif ~isfield(merged, 'inc_ang') && isfield(b, 'inc_ang')
    merged.inc_ang = [nan(n_existing, 1); b.inc_ang(:)];
end

if isfield(a, 't_axis')
    merged.t_axis = a.t_axis;
end
if isfield(a, 'fs_eff')
    merged.fs_eff = a.fs_eff;
end
end

function validate_merge_compatibility(a, b, params)
assert_same_cir_width('CIR_rx1', a, b);
assert_same_cir_width('CIR_rx2', a, b);
assert_internal_cir_width(a, 'a');
assert_internal_cir_width(b, 'b');

has_t_axis_a = isfield(a, 't_axis');
has_t_axis_b = isfield(b, 't_axis');
if xor(has_t_axis_a, has_t_axis_b)
    error('[merge_sim_data] t_axis field presence mismatch.');
end
if has_t_axis_a && has_t_axis_b
    t_axis_tol_ns = get_param(params, 'merge_t_axis_tol_ns', 1e-9);
    t_axis_a = double(a.t_axis(:));
    t_axis_b = double(b.t_axis(:));
    if numel(t_axis_a) ~= numel(t_axis_b)
        error('[merge_sim_data] t_axis length mismatch (%d vs %d).', numel(t_axis_a), numel(t_axis_b));
    end
    if any(abs(t_axis_a - t_axis_b) > t_axis_tol_ns)
        error('[merge_sim_data] t_axis mismatch exceeds tolerance %.3g ns.', t_axis_tol_ns);
    end

    if isfield(a, 'CIR_rx1') && size(a.CIR_rx1, 2) ~= numel(t_axis_a)
        error('[merge_sim_data] a.CIR_rx1 width and t_axis length mismatch.');
    end
    if isfield(b, 'CIR_rx1') && size(b.CIR_rx1, 2) ~= numel(t_axis_b)
        error('[merge_sim_data] b.CIR_rx1 width and t_axis length mismatch.');
    end
end

has_fs_a = isfield(a, 'fs_eff');
has_fs_b = isfield(b, 'fs_eff');
if xor(has_fs_a, has_fs_b)
    error('[merge_sim_data] fs_eff field presence mismatch.');
end
if has_fs_a && has_fs_b
    fs_tol_hz = get_param(params, 'merge_fs_eff_tol_hz', 1e-3);
    fs_a = double(a.fs_eff);
    fs_b = double(b.fs_eff);
    if ~isfinite(fs_a) || ~isfinite(fs_b)
        error('[merge_sim_data] fs_eff must be finite.');
    end
    if abs(fs_a - fs_b) > fs_tol_hz
        error('[merge_sim_data] fs_eff mismatch exceeds tolerance %.3g Hz.', fs_tol_hz);
    end
end
end

function assert_same_cir_width(field_name, a, b)
if ~isfield(a, field_name) || ~isfield(b, field_name)
    return;
end
width_a = size(a.(field_name), 2);
width_b = size(b.(field_name), 2);
if width_a ~= width_b
    error('[merge_sim_data] %s width mismatch (%d vs %d).', field_name, width_a, width_b);
end
end

function assert_internal_cir_width(sim_data, sim_name)
if ~isfield(sim_data, 'CIR_rx1') || ~isfield(sim_data, 'CIR_rx2')
    return;
end
if size(sim_data.CIR_rx1, 2) ~= size(sim_data.CIR_rx2, 2)
    error('[merge_sim_data] %s has inconsistent CIR widths between rx1 and rx2.', sim_name);
end
end

function n_sample = get_sample_count(sim_data)
if isfield(sim_data, 'CIR_rx1')
    n_sample = size(sim_data.CIR_rx1, 1);
elseif isfield(sim_data, 'pos_id')
    n_sample = numel(sim_data.pos_id);
else
    n_sample = 0;
end
end
