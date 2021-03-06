%% Get valid balls belonging to a trial

function filt = get_valid_balls(filt,balls1,balls3)

t_start = balls3(1,1);
t_end = balls1(end,1);

% if isempty(idx_begin)
%     idx_begin = 0; %idx_begin = 3300; % if we cut the recordings
% end
idx_begin = 0;
idx_start = 500 * t_start - idx_begin;
idx_end = 500 * t_end - idx_begin;

filt = filt(idx_start:idx_end,:);