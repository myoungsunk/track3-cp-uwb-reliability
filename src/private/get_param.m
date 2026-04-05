function value = get_param(params, field_name, default_value)
% GET_PARAM Return params.(field_name) if available; otherwise default_value.
if nargin < 1 || isempty(params)
    value = default_value;
    return;
end

if isfield(params, field_name) && ~isempty(params.(field_name))
    value = params.(field_name);
else
    value = default_value;
end
end

