function freq_table = load_sparam_table(filepath, params)
% LOAD_SPARAM_TABLE Load S-parameter CSV/MAT and normalize rows into freq_table.
if nargin < 2
    params = struct();
end

if ~(ischar(filepath) || isstring(filepath))
    error('[load_sparam_table] filepath must be char/string.');
end

filepath = char(filepath);
if ~isfile(filepath)
    error('[load_sparam_table] file not found: %s', filepath);
end

[~, file_name, file_ext] = fileparts(filepath);
file_ext = lower(file_ext);

if strcmp(file_ext, '.csv')
    raw_table = readtable(filepath, 'VariableNamingRule', 'modify');
elseif strcmp(file_ext, '.mat')
    loaded = load(filepath);
    raw_table = get_table_from_mat(loaded, filepath);
else
    error('[load_sparam_table] unsupported file extension: %s', file_ext);
end

raw_names = raw_table.Properties.VariableNames;

col_x = resolve_column(raw_names, get_param(params, 'col_x', ''), ...
    {'x_coord_n_', 'x_coord_mm_', 'x_coord_mm', 'x_coord', 'x', 'x_m'});
col_y = resolve_column(raw_names, get_param(params, 'col_y', ''), ...
    {'y_coord_n_', 'y_coord_mm_', 'y_coord_mm', 'y_coord', 'y', 'y_m'});
col_freq = resolve_column(raw_names, get_param(params, 'col_freq', ''), ...
    {'Freq_GHz_', 'freq_ghz', 'freq_ghz_', 'freq', 'frequency_ghz_'});

input_format = lower(string(get_param(params, 'input_format', 'mp')));
if input_format ~= "mp" && input_format ~= "ri"
    error('[load_sparam_table] params.input_format must be ''mp'' or ''ri''.');
end

has_cp4_channels = false;
S21_rhcp_rx1 = [];
S21_rhcp_rx2 = [];
S21_lhcp_rx1 = [];
S21_lhcp_rx2 = [];

if input_format == "mp"
    col_mag_rx1 = resolve_column(raw_names, get_param(params, 'col_mag_rx1', ''), ...
        {'mag_S_rx1_p1_tx_p1___', 'mag_S21_', 'mag_S21', 'mag_s21', 'mag_s_rx1_p1_tx_p1'});
    col_phase_rx1 = resolve_column(raw_names, first_nonempty( ...
        get_param(params, 'col_phase_rx1', ''), get_param(params, 'col_ang_rx1', '')), ...
        {'ang_deg_S_rx1_p1_tx_p1___deg_', 'pha_S21_', 'phase_S21_', 'ang_deg_S21_', 'ang_deg_s_rx1_p1_tx_p1'});

    col_mag_rx2 = resolve_column(raw_names, get_param(params, 'col_mag_rx2', ''), ...
        {'mag_S_rx2_p1_tx_p1___', 'mag_S31_', 'mag_S31', 'mag_s31', 'mag_s_rx2_p1_tx_p1'});
    col_phase_rx2 = resolve_column(raw_names, first_nonempty( ...
        get_param(params, 'col_phase_rx2', ''), get_param(params, 'col_ang_rx2', '')), ...
        {'ang_deg_S_rx2_p1_tx_p1___deg_', 'pha_S31_', 'phase_S31_', 'ang_deg_S31_', 'ang_deg_s_rx2_p1_tx_p1'});

    mag_rx1 = double(raw_table.(col_mag_rx1));
    mag_rx2 = double(raw_table.(col_mag_rx2));
    phase_rx1 = double(raw_table.(col_phase_rx1));
    phase_rx2 = double(raw_table.(col_phase_rx2));

    phase_unit = lower(string(get_param(params, 'phase_unit', 'deg')));
    if phase_unit == "deg"
        phase_rx1_rad = deg2rad(phase_rx1);
        phase_rx2_rad = deg2rad(phase_rx2);
    elseif phase_unit == "rad"
        phase_rx1_rad = phase_rx1;
        phase_rx2_rad = phase_rx2;
    else
        error('[load_sparam_table] params.phase_unit must be ''deg'' or ''rad''.');
    end

    S21_rx1 = mag_rx1 .* exp(1j * phase_rx1_rad);
    S21_rx2 = mag_rx2 .* exp(1j * phase_rx2_rad);

    % Optional 4-channel CP columns:
    %   RHCP_rx1, LHCP_rx1, RHCP_rx2, LHCP_rx2
    S21_rhcp_rx1 = S21_rx1;
    S21_rhcp_rx2 = S21_rx2;

    col_mag_lhcp_rx1 = try_resolve_column(raw_names, get_param(params, 'col_mag_lhcp_rx1', ''), ...
        {'mag_S_LHCP_rx1_p1_tx_p1___', 'mag_s_lhcp_rx1_p1_tx_p1'});
    col_phase_lhcp_rx1 = try_resolve_column(raw_names, first_nonempty( ...
        get_param(params, 'col_phase_lhcp_rx1', ''), get_param(params, 'col_ang_lhcp_rx1', '')), ...
        {'ang_deg_S_LHCP_rx1_p1_tx_p1___deg_', 'ang_deg_s_lhcp_rx1_p1_tx_p1'});
    col_mag_lhcp_rx2 = try_resolve_column(raw_names, get_param(params, 'col_mag_lhcp_rx2', ''), ...
        {'mag_S_LHCP_rx2_p1_tx_p1___', 'mag_s_lhcp_rx2_p1_tx_p1'});
    col_phase_lhcp_rx2 = try_resolve_column(raw_names, first_nonempty( ...
        get_param(params, 'col_phase_lhcp_rx2', ''), get_param(params, 'col_ang_lhcp_rx2', '')), ...
        {'ang_deg_S_LHCP_rx2_p1_tx_p1___deg_', 'ang_deg_s_lhcp_rx2_p1_tx_p1'});

    has_lhcp_cols = all(strlength([col_mag_lhcp_rx1, col_phase_lhcp_rx1, col_mag_lhcp_rx2, col_phase_lhcp_rx2]) > 0);
    if has_lhcp_cols
        mag_lhcp_rx1 = double(raw_table.(char(col_mag_lhcp_rx1)));
        mag_lhcp_rx2 = double(raw_table.(char(col_mag_lhcp_rx2)));
        phase_lhcp_rx1 = double(raw_table.(char(col_phase_lhcp_rx1)));
        phase_lhcp_rx2 = double(raw_table.(char(col_phase_lhcp_rx2)));

        if phase_unit == "deg"
            phase_lhcp_rx1_rad = deg2rad(phase_lhcp_rx1);
            phase_lhcp_rx2_rad = deg2rad(phase_lhcp_rx2);
        else
            phase_lhcp_rx1_rad = phase_lhcp_rx1;
            phase_lhcp_rx2_rad = phase_lhcp_rx2;
        end

        S21_lhcp_rx1 = mag_lhcp_rx1 .* exp(1j * phase_lhcp_rx1_rad);
        S21_lhcp_rx2 = mag_lhcp_rx2 .* exp(1j * phase_lhcp_rx2_rad);
        has_cp4_channels = true;
    end
else
    col_re_rx1 = resolve_column(raw_names, get_param(params, 'col_re_rx1', ''), ...
        {'re_S_rx1_p1_tx_p1___', 'real_S21_', 're_S21_', 're_s21'});
    col_im_rx1 = resolve_column(raw_names, get_param(params, 'col_im_rx1', ''), ...
        {'im_S_rx1_p1_tx_p1___', 'imag_S21_', 'im_S21_', 'im_s21'});
    col_re_rx2 = resolve_column(raw_names, get_param(params, 'col_re_rx2', ''), ...
        {'re_S_rx2_p1_tx_p1___', 'real_S31_', 're_S31_', 're_s31'});
    col_im_rx2 = resolve_column(raw_names, get_param(params, 'col_im_rx2', ''), ...
        {'im_S_rx2_p1_tx_p1___', 'imag_S31_', 'im_S31_', 'im_s31'});

    S21_rx1 = double(raw_table.(col_re_rx1)) + 1j * double(raw_table.(col_im_rx1));
    S21_rx2 = double(raw_table.(col_re_rx2)) + 1j * double(raw_table.(col_im_rx2));
end

x_raw = double(raw_table.(col_x));
y_raw = double(raw_table.(col_y));
freq_ghz = double(raw_table.(col_freq));

coord_unit = lower(string(get_param(params, 'coord_unit', 'mm')));
if coord_unit == "mm"
    x_coord_mm = x_raw;
    y_coord_mm = y_raw;
elseif coord_unit == "m"
    x_coord_mm = x_raw * 1e3;
    y_coord_mm = y_raw * 1e3;
else
    error('[load_sparam_table] params.coord_unit must be ''mm'' or ''m''.');
end

col_inc = try_resolve_column(raw_names, get_param(params, 'col_inc_ang', ''), ...
    {'inc_ang_deg_', 'inc_ang_deg', 'inc_ang', 'anc_ang_deg_', 'anc_ang'});
has_inc_ang = strlength(col_inc) > 0;
if has_inc_ang
    inc_ang_deg = double(raw_table.(char(col_inc)));
else
    inc_ang_deg = nan(height(raw_table), 1);
end

[pol_type, case_id] = parse_file_tags(file_name);

valid_mask = isfinite(x_coord_mm) & isfinite(y_coord_mm) & isfinite(freq_ghz) & ...
    isfinite(real(S21_rx1)) & isfinite(imag(S21_rx1)) & ...
    isfinite(real(S21_rx2)) & isfinite(imag(S21_rx2));

if has_cp4_channels
    valid_mask = valid_mask & ...
        isfinite(real(S21_rhcp_rx1)) & isfinite(imag(S21_rhcp_rx1)) & ...
        isfinite(real(S21_lhcp_rx1)) & isfinite(imag(S21_lhcp_rx1)) & ...
        isfinite(real(S21_rhcp_rx2)) & isfinite(imag(S21_rhcp_rx2)) & ...
        isfinite(real(S21_lhcp_rx2)) & isfinite(imag(S21_lhcp_rx2));
end

if any(~valid_mask)
    warning('[load_sparam_table] %d rows dropped due to non-finite values.', sum(~valid_mask));
end

x_coord_mm = x_coord_mm(valid_mask);
y_coord_mm = y_coord_mm(valid_mask);
freq_ghz = freq_ghz(valid_mask);
S21_rx1 = S21_rx1(valid_mask);
S21_rx2 = S21_rx2(valid_mask);
inc_ang_deg = inc_ang_deg(valid_mask);
if has_cp4_channels
    S21_rhcp_rx1 = S21_rhcp_rx1(valid_mask);
    S21_lhcp_rx1 = S21_lhcp_rx1(valid_mask);
    S21_rhcp_rx2 = S21_rhcp_rx2(valid_mask);
    S21_lhcp_rx2 = S21_lhcp_rx2(valid_mask);
end

if has_inc_ang
    group_keys = [x_coord_mm, y_coord_mm, inc_ang_deg];
else
    group_keys = [x_coord_mm, y_coord_mm];
end
[~, ~, group_id] = unique(group_keys, 'rows', 'stable');
group_id = uint32(group_id);

n_row = numel(group_id);
pol_type_col = repmat(string(pol_type), n_row, 1);
case_id_col = repmat(string(case_id), n_row, 1);

freq_table = table( ...
    x_coord_mm, ...
    y_coord_mm, ...
    freq_ghz, ...
    S21_rx1, ...
    S21_rx2, ...
    group_id, ...
    pol_type_col, ...
    case_id_col, ...
    'VariableNames', {'x_coord_mm', 'y_coord_mm', 'freq_ghz', 'S21_rx1', 'S21_rx2', 'group_id', 'pol_type', 'case_id'});

if has_inc_ang
    freq_table.inc_ang_deg = inc_ang_deg;
end

if has_cp4_channels
    freq_table.S21_rhcp_rx1 = S21_rhcp_rx1;
    freq_table.S21_lhcp_rx1 = S21_lhcp_rx1;
    freq_table.S21_rhcp_rx2 = S21_rhcp_rx2;
    freq_table.S21_lhcp_rx2 = S21_lhcp_rx2;
end
end

function col_name = resolve_column(var_names, explicit_name, candidates)
if nargin < 2
    explicit_name = '';
end

explicit_name = string(explicit_name);
if strlength(explicit_name) > 0
    if any(strcmp(var_names, explicit_name))
        col_name = char(explicit_name);
        return;
    end

    try
        found = find_column_name(var_names, {char(explicit_name)}, false);
        if strlength(found) > 0
            col_name = char(found);
            return;
        end
    catch %#ok<CTCH>
    end
end

found = find_column_name(var_names, candidates, true);
col_name = char(found);
end

function col_name = try_resolve_column(var_names, explicit_name, candidates)
col_name = "";
try
    col_name = string(resolve_column(var_names, explicit_name, candidates));
catch %#ok<CTCH>
    col_name = "";
end
end

function value = first_nonempty(varargin)
value = '';
for idx = 1:nargin
    candidate = string(varargin{idx});
    if strlength(candidate) > 0
        value = char(candidate);
        return;
    end
end
end

function table_out = get_table_from_mat(loaded_struct, filepath)
field_names = fieldnames(loaded_struct);
for idx = 1:numel(field_names)
    value = loaded_struct.(field_names{idx});
    if istable(value)
        table_out = value;
        return;
    end
end
for idx = 1:numel(field_names)
    value = loaded_struct.(field_names{idx});
    if isstruct(value) && isscalar(value)
        try
            table_out = struct2table(value, 'AsArray', true);
            return;
        catch %#ok<CTCH>
        end
    end
end
error('[load_sparam_table] no table-like variable in MAT file: %s', filepath);
end

function [pol_type, case_id] = parse_file_tags(file_name)
file_name = lower(string(file_name));
if startsWith(file_name, "cp")
    pol_type = "CP";
elseif startsWith(file_name, "lp")
    pol_type = "LP";
else
    pol_type = "UNKNOWN";
    warning('[load_sparam_table] polarization tag not parsed from filename: %s', file_name);
end

tokens = regexp(char(file_name), 'case([abc])', 'tokens', 'once');
if isempty(tokens)
    case_id = "UNKNOWN";
    warning('[load_sparam_table] case tag not parsed from filename: %s', file_name);
else
    case_id = "case" + upper(string(tokens{1}));
end
end
