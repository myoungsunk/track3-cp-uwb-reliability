function column_name = find_column_name(variable_names, candidates, required)
% FIND_COLUMN_NAME Find first matching column name from candidate list.
if nargin < 3
    required = true;
end

if isstring(variable_names)
    variable_names = cellstr(variable_names);
end
if isstring(candidates)
    candidates = cellstr(candidates);
end

normalized_variables = cellfun(@normalize_name, variable_names, "UniformOutput", false);
column_name = "";

for candidate_index = 1:numel(candidates)
    candidate_normalized = normalize_name(candidates{candidate_index});
    matched_index = find(strcmp(normalized_variables, candidate_normalized), 1, "first");
    if ~isempty(matched_index)
        column_name = string(variable_names{matched_index});
        return;
    end
end

if required
    error("Required column not found. Candidates: %s", strjoin(candidates, ", "));
end
end

function normalized_name = normalize_name(raw_name)
normalized_name = lower(regexprep(strtrim(char(raw_name)), "[^a-zA-Z0-9]", ""));
end

