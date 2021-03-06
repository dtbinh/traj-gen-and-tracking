% Model based Iterative Learning Control 
%
% where F is the lifted matrix of the plant dynamics
% and L is the learning matrix of the ILC update i.e.
% unext = ulast - L*error;
%
% Ideally L = pinv(F), a model-based ILC update rule
%

classdef mILC < ILC
    
    % fields common to all ILCs (defined in abstract ILC class)
    properties
         
        % number of total episodes so far
        episode
        % color of particular controller
        color
        % name of the particular controller
        name
        % costs incurred (Q-SSE)
        error
        % downsampling to speed things up
        downsample
        % final cost
        finalCost
        % initial error last
        e0_last
        % ILC's Last input sequence
        inp_last
        % Lifted state matrix F (input-state) and G (state-output)
        F
        G
        % Lifted penalty matrices Q and R 
        Ql
        Rl
        % holding Finv in case F matrix is very big
        Finv
        % holding response of initial error
        H
        
        % flag for simulation method
        flagMethod
    end
    
    methods
        
        %% Constructor for model-based ILC
        function obj = mILC(model,trj,varargin)
                        
            obj.episode = 0;
            obj.color = 'm';
            obj.name = 'Model-based ILC';
            obj.error = 0;
            obj.downsample = 1;
            obj.flagMethod = 1;
            
            if nargin >= 3
                obj.downsample = min(varargin{1},10);
            end
            
            if nargin == 4
                obj.flagMethod = varargin{2};
            end
            
            trj = trj.downsample(obj.downsample);
            
            dim_x = model.SIM.dimx;
            dim_u = model.SIM.dimu;
            dim_y = model.SIM.dimy;
            
            N = trj.N - 1;
            
            if ~isempty(trj.unom)
                obj.inp_last = trj.unom(:,1:N);
            else
                warning('Using last performance results');
                obj.inp_last = trj.PERF(end).u;
            end
            
            obj.F = zeros(N*dim_x, N*dim_u);
            obj.H = zeros(N*dim_x, dim_x);
            obj.G = zeros(N*dim_y, N*dim_x);
            obj.Ql = zeros(N*dim_y, N*dim_y);
            obj.Rl = zeros(N*dim_u, N*dim_u);
            
            obj.e0_last = zeros(dim_x,1);
            
            obj.lift(model,trj);
            %L = 0.5 * eye(size(obj.F,2));
            %obj.Finv = (obj.F' * obj.F + L)\(obj.F');
            obj.Finv = pinv(obj.F,0.05); % takes much more time!
            
        end
        
        %% get the lifted vector representation 
        % around the trajectory
        function lift(obj,model,trj)
            
            N = trj.N - 1;
            
            dim_x = model.SIM.dimx;
            dim_u = model.SIM.dimu;
            
            % deal C matrix to G
            obj.G = cell(1,N);
            obj.Ql = cell(1,N);
            obj.Rl = cell(1,N);
            % TODO: this could also be time varying!
            [obj.G{:}] = deal(model.C);
            [obj.Ql{:}] = deal(model.COST.Q);
            [obj.Rl{:}] = deal(model.COST.R);
            obj.G = blkdiag(obj.G{:});
            obj.Ql = blkdiag(obj.Ql{:});
            obj.Rl = blkdiag(obj.Rl{:});
            
            if isa(model,'Linear')
                % K = trj.K;
                Ad = model.Ad;
                Bd = model.Bd;
                % construct lifted domain matrix F
                % TODO: this can be computed much more efficiently
                % for linear systems
                for i = 1:N
                    vec_x = (i-1)*dim_x + 1:i*dim_x;
                    for j = 1:i                            
                        vec_u = (j-1)*dim_u + 1:j*dim_u;
                        mat = Bd;
                        for k = j+1:i
                            mat = Ad * mat; % (Ad + Bd * K(:,:,k)) * mat;
                        end
                        obj.F(vec_x,vec_u) = mat; % on diagonals only B(:,m)
                    end
                    obj.H(vec_x,:) = Ad ^ i;
                end                
            else
                % get linear time variant matrices around trajectory
                [Ad,Bd] = model.linearize(trj);
                % K = trj.K;
                % construct lifted domain matrix F
                for i = 1:N
                    vec_x = (i-1)*dim_x + 1:i*dim_x;
                    matH = eye(dim_x);
                    for j = 1:i                            
                        vec_u = (j-1)*dim_u + 1:j*dim_u;
                        matH = matH * Ad(:,:,j);
                        mat = Bd(:,:,j);
                        for k = j+1:i
                            mat = Ad(:,:,k) * mat; % (Ad(:,:,k) + Bd(:,:,k)*K(:,:,k)) * mat;
                        end
                        obj.F(vec_x,vec_u) = mat; % on diagonals only B(:,m)
                    end
                    obj.H(vec_x,:) = matH;

                end
            end
            
            obj.F = obj.G * obj.F;
            obj.H = obj.G * obj.H;
            
        end
        
        %% Main ILC function applying Newton's method typically
        function u = feedforward(obj,trj,y)
            
            trj = trj.downsample(obj.downsample);
            dimu = size(obj.inp_last,1);
            Nu = size(obj.inp_last,2);
            N = Nu + 1;
            rate = size(y,2)/N;
            idx = rate * (1:N);
            y = y(:,idx);            
            e = y - trj.s;
            e = e(:,2:end);                        
            Sl = 1 * obj.Rl; % we keep du penalty S same as R
            
            % gradient descent
            %u = obj.inp_last(:) - 1e-10 * obj.F' * obj.Ql * e(:);
            % model inversion based Newton-Raphson update
            u = obj.inp_last(:) - obj.F \ e(:);
            % more stable inverse based Newton-Raphson update
            % computes very high inverses though
            %u = obj.inp_last(:) - pinv(obj.F,0.2) * e(:);
            % in case F is very large
            %u = obj.inp_last(:) - obj.Finv * e(:);
            % Penalize inputs and derivatives (LM-type update)
            %Q = pinv(obj.F' * obj.Ql * obj.F + obj.Rl + Sl) * (obj.F' * obj.Ql * obj.F + Sl);
            %L = pinv(obj.F' * obj.Ql * obj.F + Sl) * (obj.F' * obj.Ql);
            %u = obj.inp_last(:) - L * e(:);                        
            %u = Q * (obj.inp_last(:) - L * e(:));
            % Mayer form
            %{
            M = zeros(size(obj.Ql));
            M(end-2*dimu+1:end,end-2*dimu+1:end) = 1;
            Mat = pinv(obj.F' * M * obj.F + Sl) * (obj.F' * M);
            u = obj.inp_last(:) - Mat * e(:);
            %}
            % Iterative Method with Conjugate gradient
            %A = obj.F' * obj.Ql * obj.F + Sl;
            %u = obj.inp_last(:) - cgs(A,obj.F'*obj.Ql*e(:));
            % Total Least Squares
            %u = obj.inp_last(:) - tls(obj.F,e(:),0.2);
            
            % revert from lifted vector from back to normal form
            u = reshape(u,dimu,Nu);
            
            trj.unom = u;
            trj = trj.upsample(obj.downsample);
            u = trj.unom;
            
        end
        
        %% Feedforward compensation for DMP with different I.C.
        function u = feedforwardDMP(obj,trj,y,ulast,e0)
            
            trj = trj.downsample(obj.downsample);
            dimx = size(trj.s,1);
            dimu = size(obj.inp_last,1);
            Nu = size(obj.inp_last,2);
            N = Nu + 1;
            rate = size(y,2)/N;
            idx = rate * (1:N);
            y = y(:,idx);
            ulast = ulast(:,idx(1:end-1));
            e = y - trj.s;
            e0diff = e0 - obj.e0_last;
            obj.e0_last = e0;
            e = e(:,2:end);        
            % we keep du penalty S proportional to R
            
            switch obj.flagMethod
                
                case 1
                    % usual MILC
                    Sl = obj.Rl;
                    %u = ulast(:) - obj.Finv * e(:);
                    L = pinv(obj.F' * obj.Ql * obj.F + Sl,0.05) * (obj.F' * obj.Ql);
                    u = obj.inp_last(:) - L * e(:);
                case 2
                    % correct for e0            
                    err = e(:); % + obj.H * e0diff;
                    % Mayer form
                    % Exponential weighting does not work for some reason!!
                    %{
                    M = 1:Nu; %exp(1:Nu);
                    M = M/sum(M);
                    M = repmat(M,dimx,1);
                    M = M(:);
                    %M(M < 0.01) = eps;
                    M = diag(M);
                    %}
                    M = zeros(size(obj.Ql));
                    M(end-2*dimu+1:end,end-2*dimu+1:end) = 1;
                    %Mat = (obj.F' * M * obj.F + Sl) \ (obj.F' * M);
                    Mat = pinv(obj.F' * M * obj.F,0.05) * (obj.F' * M);
                    %Mat = obj.F' * M;
                    u = ulast(:) - Mat * err;
                otherwise
                    u = ulast(:);
            end
            
            
            % revert from lifted vector from back to normal form
            u = reshape(u,dimu,Nu);
            
            trj.unom = u;
            trj = trj.upsample(obj.downsample);
            u = trj.unom;
            
        end
    end
    
end