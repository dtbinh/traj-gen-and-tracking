%% Table Tennis class for simulating a solo game

classdef TableTennis3D < handle
    
    properties
        
        % sampling time
        dt
        % planning related parameters are stored here
        plan
        % table related parameters
        table
        % net is useful for strategies
        net
        % ball class
        ball
        % environmental contraints
        wall, floor
        % robot 
        robot
        % handle structure for drawing animation
        handle
        % draw flag (structure)
        draw
        % noise models (as a structure)
        noise
        % build offline policy (a structure)
        offline
        % time to reach desired point on opponents court
        time2reach
        
    end
    
    methods
        
        %% CONSTRUCTOR AND SUBMETHODS
        function obj = TableTennis3D(wam,dt,q0,opt)
            
            % time to reach desired point on opponents court
            obj.time2reach = 0.8; 
            % sampling time
            obj.dt = dt;
            % initialize the robot
            obj.robot = wam;            
            % initialize camera noise
            obj.noise.camera.cov = opt.camera.cov;            
            % initialize a ball    
            obj.ball = Ball3D(opt.distr); 
            
            % choose method to use for generating trajectories                        
            obj.plan.method = opt.plan.method;
            obj.plan.vhp.y = opt.plan.vhp.y;
            
            obj.reset_plan(q0);
            obj.init_lookup(opt);
            obj.init_table(); 
            obj.init_handle(opt,q0);   
            
        end
        
        % reset planning
        function reset_plan(obj,q0)
            WAIT = 0;
            obj.plan.stage = WAIT;
            obj.plan.obs = [];
            obj.plan.idx = 1;
            obj.plan.q = q0;
            obj.plan.qd = zeros(7,1);
        end
        
        % initialize table parameters
        function init_table(obj)
            
            loadTennisTableValues();
            % table related values
            obj.table.Z = table_z;
            obj.table.WIDTH = table_width;
            obj.table.LENGTH = table_length;
            obj.table.DIST = dist_to_table;
            % coeff of restitution-friction vector
            obj.table.K = [CFTX; CFTY; -CRT];
            
            % net y value and coeff of restitution of net
            obj.net.Y = dist_to_table - table_y;
            obj.net.Xmax = table_width/2 + net_overhang;
            obj.net.Zmax = table_z + net_height;
            obj.net.CRN = net_restitution;    
            
            % environment constraints                        
            obj.wall = 1.0;
            obj.floor = floor_level;
        end
        
        % init handle for recording video and drawing
        function init_handle(obj,opt,q0)            
            % initialize animation
            obj.draw = opt.draw;
            if opt.draw.setup                
                obj.initAnimation(q0);
                obj.handle.record = false;
                if opt.record
                    obj.handle.record = true;
                    filename = sprintf('tableTennisSim%d.avi',randi(100));
                    obj.handle.recordFile = VideoWriter(filename);
                    open(obj.handle.recordFile);
                end
            else
                obj.handle = [];
                obj.handle.record = false;
            end
        end
        
        % initialize the lookup table parameters
        function init_lookup(obj,opt)
            
            % shall we train an offline lookup table
            obj.offline.train = opt.train;
            obj.offline.use = opt.lookup.flag;
            obj.offline.mode = opt.lookup.mode;
            obj.offline.savefile = opt.lookup.savefile;
            obj.offline.X = [];
            obj.offline.Y = [];
            
            if obj.offline.use || obj.offline.train
                try
                    % load the savefile
                    load(obj.offline.savefile,'X','Y');
                    obj.offline.X = X;
                    obj.offline.Y = Y;
                    obj.offline.B = X \ Y;
                    if strcmp(obj.offline.mode,'GP-regress')
                        obj.train_gp(X,Y); 
                    end
                catch
                    warning('No lookup table found!');
                    obj.offline.X = [];
                    obj.offline.Y = [];
                end
            end            
        end
        
        % Train independent GPS
        function train_gp(obj,X,Y)            
            hp.type = 'squared exponential iso';
            hp.l = 1/4;
            hp.scale = 1;
            hp.noise.var = 0.0;
            ndofs = 7;
            num_dims = 2*ndofs + 1;
            for i = 1:num_dims
                gp{i} = GP(hp,X',Y(:,i));
            end
            obj.offline.GP = gp;            
        end
        
        %% MAIN LOOP
        
        % first robot practices 
        function numLands = practice(obj,q0,numTimes)
        
            numLands = 0;
            eps = obj.noise.camera.cov;
            maxSimTime = 3.0;
            
            for i = 1:numTimes                                               
                % reset the ball state
                obj.ball.resetState();
                % play one turn
                obj.playOneTurn(q0,maxSimTime);                
                % check landing
                if obj.ball.isLANDED
                    numLands = numLands + 1;
                    % build offline policy
                    if obj.offline.train                        
                        obj.offline.X = [obj.offline.X; obj.offline.b0];
                        obj.offline.Y = [obj.offline.Y; obj.offline.xf];
                    end                    
                end
                fprintf('Iteration: %d\n', i);
                obj.reset_plan(q0);
            end
            
            fprintf('Landed %d/%d.\n',numLands,numTimes);
            if obj.offline.train && ~obj.offline.use
                % save them
                X = obj.offline.X;
                Y = obj.offline.Y;
                save(obj.offline.savefile,'X','Y');
            end
            
            % make sure recording is closed
            if obj.handle.record
                close(obj.handle.recordFile);
            end
        end
        
        % first robot plays solo once
        function playOneTurn(obj,q0,timeMax)
            
            timeSim = 0.0;
            % initialize q and x
            qd0 = zeros(7,1);
            [x,xd,o] = obj.robot.calcRacketState(q0,qd0);     
            % Init filter
            eps = 1e4;
            ballCovEst = eps;
            ballPosEst = [0.0;obj.table.DIST + obj.table.LENGTH; obj.table.Z + 0.2];
            ballVelEst = [0.0;4.0;4.0];
            filter = obj.initFilter(ballPosEst,ballVelEst,ballCovEst);

            while timeSim < timeMax                
                % evolve ball according to racket and get estimate
                filter = obj.getBallEstimate(filter,x,xd,o);
                [q,qd] = obj.planFiniteStateMachine(filter,q0);
                [x,xd,o] = obj.robot.calcRacketState(q,qd);                
                if obj.draw.setup
                    obj.updateAnimation(q);
                end
                timeSim = timeSim + obj.dt;                
            end
            
            % clear the ball path predicted and robot generated traj
            if obj.draw.setup 
                set(obj.handle.robotCartesian,'Visible','off');
                if isfield(obj.handle,'ballPredIn')
                    set(obj.handle.ballPredIn,'Visible','off');
                end
                if isfield(obj.handle,'ballActOut') 
                    set(obj.handle.ballActOut,'Visible','off');
                end
            end
        end
        
        %% STRATEGIES/TRAJ GEN FOR TABLE TENNIS
        
        % planning using a Virtual planning plane (VPP)
        % generally over the net
        % using a Finite State Machine to plan when to hit/stop
        function [q,qd] = planFiniteStateMachine(obj,filter,q0)
            
            % If it is coming towards the robot consider predicting
            velEst = filter.x(4:6);
            if velEst(2) > 0 && obj.plan.stage == 0 % WAIT
                obj.plan.stage = 1; % PREDICT
            end

            table_center = obj.table.DIST - obj.table.LENGTH/2;   
            % if stage is at PREDICT
            if obj.plan.stage == 1 && filter.x(2) > table_center && filter.x(5) > 0.5   
                switch obj.plan.method
                    case 'DEFENSIVE'
                        obj.defensive_player(q0,filter);
                    case 'FOCUSED'
                        obj.focused_player(q0,filter);
                    case 'VHP'
                        % VHP implementation is similar to
                        % focused player but with hitting plane fixed
                        obj.focused_player(q0,filter);
                    otherwise
                        error('Alg not specified!');
                end
               
            end    

            % Move the robot
            if obj.plan.stage == 2 % HIT
                obj.plan.idx = obj.plan.idx+1;
            end
            % if movement finished revert to waiting
            if obj.plan.idx > size(obj.plan.q,2)
                obj.plan.idx = size(obj.plan.q,2);
                obj.plan.stage = 3; % FINISH
            end
            
            q = obj.plan.q(:,obj.plan.idx);
            qd = obj.plan.qd(:,obj.plan.idx);
        end
        
        % Defensive player
        % does not fix q0, landing position, landing time
        % does not fix racket center to hit the incoming ball
        % returns at estimated landing time to arbitrary q with zero velocity
        %
        % Implementing still the finite state machine rules
        % Since we cannot run the optimization fast enough in MATLAB
        % to enable MPC like correction
        function defensive_player(obj,q0,filter)
            predictTime = 1.2;
            [ballPredIn,ballTime,numBounce,time2Passtable] = ...
                predictBallPath(obj.dt,predictTime,filter,obj.table);
            if checkBounceOnOppTable(filter,obj.table)
                obj.plan.stage = 3; % FINISH
            elseif numBounce ~= 1
                disp('Ball does not bounce once! Not hitting!');
                obj.plan.stage = 3; % FINISH
            elseif ~checkIfBallIsInsideWorkspace(obj.robot,ballPredIn)
                disp('No intersection with workspace! Not hitting!');
                obj.plan.stage = 3; % FINISH
            else
                obj.plan.idx = 0;
                obj.plan.stage = 2; % HIT
                dofs = 7; q0dot = zeros(dofs,1);
                time2return = 1.0;
                models.ball.time = ballTime;
                models.ball.pred = ballPredIn;
                models.ball.radius = obj.ball.radius;
                models.table.xmax = obj.table.WIDTH/2;
                models.wall.height = obj.wall;
                models.net.height = obj.net.Zmax;
                models.table.height = obj.table.Z;
                models.table.dist = obj.table.DIST;
                models.table.length = obj.table.LENGTH;
                models.floor.level = obj.floor;
                models.racket.radius = obj.ball.RACKET.R;
                models.gravity = abs(obj.ball.g);
                models.racket.contact = @(velIn,racket) obj.ball.racketContactModel(velIn,racket);
                
                [qf,qfdot,T] = lazyOptimPoly(obj,models,q0);
                [q,qd,qdd] = calcHitAndReturnSpline(obj.dt,q0,q0dot,qf,qfdot,T,time2return);
                [q,qd,qdd] = obj.robot.checkJointLimits(q,qd,qdd);
                [x,xd,o] = obj.robot.calcRacketState(q,qd);
                [q,qd,qdd] = obj.checkContactTable(q,qd,qdd,x);

                if obj.draw.setup 
                    % Debugging the trajectory generation                 
                    if obj.draw.robot_traj
                        obj.handle.robotCartesian = scatter3(x(1,:),x(2,:),x(3,:));
                    end

                    if obj.draw.ball.pred.in
                        obj.handle.ballPredIn = scatter3(ballPredIn(1,:),ballPredIn(2,:),ballPredIn(3,:));
                    end
                end
            
                obj.plan.q = q;
                obj.plan.qd = qd;
            end
        end
        
        
        % Centred player that tries to return the ball
        % at a desired point at a desired time
        % It fixes a q0, generates both striking and returning polynomials
        function focused_player(obj,q0,filter)
            predictTime = 1.2;
            [ballPredIn,ballTime,numBounce,time2Passtable] = ...
                predictBallPath(obj.dt,predictTime,filter,obj.table);
            if checkBounceOnOppTable(filter,obj.table)
                obj.plan.stage = 3; % FINISH
            elseif numBounce ~= 1
                disp('Ball does not bounce once! Not hitting!');
                obj.plan.stage = 3; % FINISH
            elseif ~checkIfBallIsInsideWorkspace(obj.robot,ballPredIn)
                disp('No intersection with workspace! Not hitting!');
                obj.plan.stage = 3; % FINISH
            else
                obj.plan.idx = 0;
                obj.plan.stage = 2; % HIT
                % If we're training an offline model save optimization result
                if obj.offline.train || obj.offline.use
                    obj.offline.b0 = filter.x';
                end
                obj.returnBall2Center(ballPredIn,ballTime,q0);            
            end            
        end
        
        % Fix a desired landing point and desired landing time
        % as well as a desired return time to q0
        % For now only two methods : VHP and free Time
        function returnBall2Center(obj,ballPredIn,ballTime,q0)                
            
            dofs = 7;
            % land the ball on the centre of opponents court
            ballDes(1) = 0.0;
            ballDes(2) = obj.table.DIST - 3*obj.table.LENGTH/4;
            ballDes(3) = obj.table.Z;   
            q0dot = zeros(dofs,1);
            time2return = 1.0; % time for robot to go back to q0 after hit
            
            if obj.offline.use
                [qf,qfdot,T] = obj.lookup();
            else
                % Compute traj here
                if strcmp(obj.plan.method,'VHP')
                    [qf,qfdot,T] = calcPolyAtVHP(obj.robot,obj.plan.vhp.y,obj.time2reach,ballDes,ballPredIn,ballTime,q0);
                else
                    racketDes = obj.planRacket(ballDes,ballPredIn,ballTime,obj.time2reach,q0);
                    [qf,qfdot,T] = optimPoly(obj.robot,racketDes,ballPredIn,q0,time2return);
                end
                % If we're training an offline model save optimization result
                if obj.offline.train
                    obj.offline.xf = [qf',qfdot',T];
                end
            end
            
            [q,qd,qdd] = calcHitAndReturnSpline(obj.dt,q0,q0dot,qf,qfdot,T,time2return);
            [q,qd,qdd] = obj.robot.checkJointLimits(q,qd,qdd);
            [x,xd,o] = obj.robot.calcRacketState(q,qd);
            [q,qd,qdd] = obj.checkContactTable(q,qd,qdd,x);

            if obj.draw.setup 
                % Debugging the trajectory generation                 
                if obj.draw.robot_traj
                    obj.handle.robotCartesian = scatter3(x(1,:),x(2,:),x(3,:));
                end
                
                if obj.draw.ball.pred.in
                    obj.handle.ballPredIn = scatter3(ballPredIn(1,:),ballPredIn(2,:),ballPredIn(3,:));
                end
            end

            obj.plan.q = q;
            obj.plan.qd = qd;
        end
        
        % Fix a desired landing point and desired landing time
        % and calculate racket variables over ball estimated trajectory
        function racketDes = planRacket(obj,ballDes,ballPred,ballTime,time2reach,q0)
            
            %Calculate ball outgoing velocities attached to each ball pos
            fast = true;
            tic;
            racketDes = calcRacketStrategy(ballDes,ballPred,ballTime,time2reach,fast);
            logicalStr = {'Slow','Fast'};
            fprintf('%s racket strategy calculation took %f seconds\n',...
                     logicalStr{fast + 1}, toc);
            
            % Initialize solution for optimal poly
            timeEst = 0.8;
            q0dot = zeros(length(q0),1);
            x0 = [q0;q0dot;timeEst];
            racketDes.est = x0;
        end
        
        % Check contact with table
        % IF contact is expected to occur, then 
        % Do not move the robot! [q = q0 for all time]
        function [q,qd,qdd] = checkContactTable(obj,q,qd,qdd,x)
            
             dofs = size(q,1);
             len = size(q,2);
             tol = obj.ball.RACKET.R;
             limy = obj.table.DIST;
             limx = obj.table.WIDTH;
             limz = obj.table.Z;
             assert(limy < 0, 'dist to table is negative by convention!');
             if sum((x(2,:) < limy + tol) & ...
                     (abs(x(1,:)) < limx) & ...
                     (x(3,:) < limz + tol))
                disp('Contact with table expected! Not moving the robot!');
                q0 = q(:,end);
                q = q0 * ones(1,len);
                qd = zeros(dofs,len);
                qdd = zeros(dofs,len);
             end
        end       
        
        %% LOOKUP METHODS
        % Loads lookup table parameters by finding the 
        % closest table ball-estimate entry 
        function [qf,qfdot,T] = lookup(obj)            
       
            switch obj.offline.mode
                case 'lin-regress'
                    val = obj.offline.b0 * obj.offline.B;
                case 'GP-regress'
                    dofs = 7;
                    numdims = 2*dofs + 1;
                    val = zeros(1,numdims);
                    for i = 1:numdims
                        val(i) = obj.offline.GP{i}.predict(obj.offline.b0);
                    end                
                case 'closest'      
                    [val,~] = obj.find_closest_entry();              
                otherwise
                    error('lookup mode not supported!');
            end
            dofs = (length(val) - 1) / 2;
            qf = val(1:dofs)';
            qfdot = val(dofs+1:2*dofs)';
            T = val(end);
        end 
        
        % Gets the closest entry
        function [val,idx] = find_closest_entry(obj)
            Xs = obj.offline.X;
            Ys = obj.offline.Y;
            bstar = obj.offline.b0;
            N = size(Xs,1);
            % find the closest point among Xs
            diff = repmat(bstar,N,1) - Xs;
            [~,idx] = min(diag(diff*diff'));
            val = Ys(idx,:);                
        end        
        
        %% FILTERING FOR ROBOTS TO GET BALL OBSERVATION
        
        % initialize at the center of opponents court
        function filter = initFilter(obj,posEst,velEst,covEst)
            
            % Initialize EKF
            dim = 6;
            eps = 1e-6; %1e-3;
            C = [eye(3),zeros(3)];
            tennisBall = obj.ball;

            params.C = tennisBall.C;
            params.g = tennisBall.g;
            params.radius = tennisBall.radius;
            params.zTable = obj.table.Z;
            params.yNet = obj.net.Y;
            params.table_length = obj.table.LENGTH; 
            params.table_width = obj.table.WIDTH;
            % coeff of restitution-friction vector
            params.CFTX = obj.table.K(1); 
            params.CFTY = obj.table.K(2); 
            params.CRT = -obj.table.K(3);
            params.ALG = 'RK4'; %'Euler';

            ballFlightFnc = @(x,u,dt) discreteBallFlightModel(x,dt,params);
            % very small but nonzero value for numerical stability
            mats.O = eps * eye(dim);
            mats.C = C;
            mats.M = eps * eye(3);
            filter = EKF(dim,ballFlightFnc,mats);
            filter.initState([posEst(:); velEst(:)],covEst);            
        end
        
        function obs = emulateCamera(obj)
            
            if det(obj.noise.camera.cov) > 0
                std = chol(obj.noise.camera.cov);
            else
                std = 0.0;
            end
            obs = obj.ball.pos + std * randn(3,1);
        end
        
        % Get ball estimate from cameras and update KF estimate
        % reinitialize filter whenever numobs is 12
        function filter = getBallEstimate(obj,filter,x,xd,o)
            racket.pos = x;
            racket.vel = xd;
            racketRot = quat2Rot(o);
            racket.normal = racketRot(:,3);
            dt = obj.dt;
            velPre = obj.ball.vel;
            obj.ball.evolve(dt,racket);
            velPost = obj.ball.vel;
            obs = obj.emulateCamera();
            obj.plan.obs = [obj.plan.obs, obs(:)];

            if size(obj.plan.obs,2) == 12 % re-initialize filter 
                filter = obj.reinitializeFilter(filter);
            else
                % Estimate the ball state
                filter.linearize(dt,0);
                filter.predict(dt,0);
                filter.update(obs,0);           
            end
            
            if velPre(2) > 0 && velPost(2) < 0
                % there was a hit and we can plot it
                if obj.draw.ball.act.out
                    ballPos = obj.ball.pos;
                    t = dt:dt:obj.time2reach;
                    mult = [0.9,0.9,0.8]; % multiplier
                    ballPredOut(1,:) = ballPos(1) + mult(1) * velPost(1) * t;
                    ballPredOut(2,:) = ballPos(2) + mult(2) * velPost(2) * t;
                    ballPredOut(3,:) = ballPos(3) + mult(3) * velPost(3) * t + obj.ball.g*t.*t/2;
                    obj.handle.ballActOut = scatter3(ballPredOut(1,:),ballPredOut(2,:),ballPredOut(3,:));
                end
            end
           
        end
        
        % Initialize filter based on observations so far
        function filter = reinitializeFilter(obj,filter)
            
            time = obj.dt * (1:size(obj.plan.obs,2));
            spin.flag = false;
            ballInit = estimateInitBall(time,obj.plan.obs,spin);
            covEst = 1e2;
            filter.initState(ballInit(:),covEst);
            
            for i = 1:size(obj.plan.obs,2)
                filter.linearize(obj.dt,0);
                filter.predict(obj.dt,0);
                filter.update(obj.plan.obs(:,i),0);
            end
        end
        
        %% Animation functions here
        function initAnimation(obj,q)       

            % Prepare the animation
            loadTennisTableValues();
            wam = obj.robot;
            ball = obj.ball;

            % get joints, endeffector pos and orientation
            [joint,ee,racket] = wam.drawPosture(q);
            endeff = [joint(end,1:3); ee];

            % edit: reduced to half screen size
            scrsz = get(groot,'ScreenSize');
            figure('Position',[1 scrsz(4)/2 scrsz(3)/2 scrsz(4)/2]);
            %uisetcolor is useful here to determine these 3-vectors
            orange = [0.9100 0.4100 0.1700];
            gray = [0.5020 0.5020 0.5020];
            lightgray = [0.8627    0.8627    0.8627];
            white = [0.9412 0.9412 0.9412];
            black2 = [0.3137    0.3137    0.3137];
            red = [1.0000    0.2500    0.2500];
            ballSurfX = ball.pos(1) + ball.MESH.X;
            ballSurfY = ball.pos(2) + ball.MESH.Y;
            ballSurfZ = ball.pos(3) + ball.MESH.Z;
            % transform into base coord.
            h.ball = surf(ballSurfX,ballSurfY,ballSurfZ);
            set(h.ball,'FaceColor',orange,'FaceAlpha',1,'EdgeAlpha',0);
            hold on;
            h.robot.joints = plot3(joint(:,1),joint(:,2),joint(:,3),'k','LineWidth',10);
            h.robot.endeff = plot3(endeff(:,1),endeff(:,2),endeff(:,3),'Color',gray,'LineWidth',5);
            h.robot.racket = fill3(racket(1,:), racket(2,:), racket(3,:),red);

            obj.handle = h;
            
            %title('Ball-robot interaction');
            grid on;
            axis equal;
            xlabel('x');
            ylabel('y');
            zlabel('z');
            tol_x = 0.2; tol_y = 0.1; tol_z = 0.3;
            xlim([-table_x - tol_x, table_x + tol_x]);
            ylim([dist_to_table - table_length - tol_y, 3*tol_y]);
            zlim([floor_level, table_z + 5*tol_z]);
            %legend('ball','robot');
            fill3(T(:,1),T(:,2),T(:,3),[0 0.7 0.3]);
            % faces matrix 6x4
            F = [1 2 3 4;
                 5 6 7 8;
                 1 2 6 5;
                 2 3 7 6;
                 3 4 8 7;
                 4 1 5 8];
            table = patch('Faces',F,'Vertices',T,'FaceColor',[0 0.7 0.3]);
            cdata = [0 0.7 0.3;
                     0 0.7 0.3;
                     repmat(black2,4,1)];
            set(table,'FaceColor','flat','FaceVertexCData',cdata);
            
            % plot the robot stand
            patch('Faces',F,'Vertices',SR,'FaceColor',black2);
            
            % instead draw 14 black thin lines
            numpts = 1000;
            num_horz_lines = 10;
            num_vert_lines = 50;
            tol = 0.02;
            x_nets = repmat(linspace(-table_x-net_overhang,table_x + net_overhang,numpts),num_horz_lines,1);
            y_nets = repmat(linspace(dist_to_table - table_y,dist_to_table - table_y,numpts),num_horz_lines,1);
            z_nets = repmat(linspace(table_z+tol,table_z+net_height-tol,num_horz_lines)',1,numpts);
            plot3(x_nets',y_nets',z_nets','Color',black2,'LineWidth',0.5);
            x_nets = repmat(linspace(-table_x-net_overhang,table_x + net_overhang,num_vert_lines)',1,100);
            y_nets = repmat(linspace(dist_to_table - table_y,dist_to_table - table_y,100),num_vert_lines,1);
            z_nets = repmat(linspace(table_z+tol,table_z+net_height-tol,100),num_vert_lines,1);
            plot3(x_nets',y_nets',z_nets','Color',black2,'LineWidth',0.5);
            topline_x = linspace(-table_x-net_overhang,table_x+net_overhang,numpts);
            topline_y = (dist_to_table-table_y) * ones(1,numpts);
            topline_z = (table_z + net_height) * ones(1,numpts);
            plot3(topline_x,topline_y,topline_z,'Color',white,'LineWidth',2);
            botline_x = linspace(-table_x-net_overhang,table_x+net_overhang,numpts);
            botline_y = (dist_to_table-table_y) * ones(1,numpts);
            botline_z = (table_z+tol) * ones(1,numpts);
            plot3(botline_x,botline_y,botline_z,'k','LineWidth',2);
            lefthang_x = (-table_x-net_overhang) * ones(1,100);
            lefthang_y = (dist_to_table-table_y) * ones(1,100);
            lefthang_z = linspace(table_z+tol,table_z+net_height,100);
            plot3(lefthang_x,lefthang_y,lefthang_z,'k','LineWidth',4);
            righthang_x = (table_x+net_overhang) * ones(1,100);
            plot3(righthang_x,lefthang_y,lefthang_z,'k','LineWidth',4);
            %fill3(net(:,1),net(:,2),net(:,3),[0 0 0]);
            
            % two white vert lines on the edges
            tol = 0.012;
            line1_x = repmat(linspace(-table_x+tol,table_x-tol,2)',1,numpts);
            line1_y = repmat(linspace(dist_to_table-table_length,dist_to_table,numpts),2,1);
            line1_z = repmat(table_z * ones(1,numpts),2,1);
            plot3(line1_x',line1_y',line1_z','w','LineWidth',3);
            % center vert line has less width
            line_center_x = zeros(1,numpts);
            line_center_y = linspace(dist_to_table-table_length,dist_to_table,numpts);
            line_center_z = table_z * ones(1,numpts);
            plot3(line_center_x, line_center_y, line_center_z,'w','LineWidth',1);
            % horizontal lines
            line2_x = repmat(linspace(-table_x,table_x,numpts),2,1);
            line2_y = repmat(linspace(dist_to_table-table_length+tol,dist_to_table-tol,2)',1,numpts);
            line2_z = repmat(table_z * ones(1,numpts),2,1);
            plot3(line2_x',line2_y',line2_z','w','LineWidth',5);
            
            % fill also the virtual hitting plane
            if strcmp(obj.plan.method,'VHP')
                V1 = [table_center - table_x; 
                    obj.plan.vhp.y;
                    table_z - 2*tol_z];
                V2 = [table_center + table_x;
                    obj.plan.vhp.y;
                    table_z - 2*tol_z];
                V3 = [table_center + table_x;
                    obj.plan.vhp.y;
                    table_z + 2*tol_z];
                V4 = [table_center - table_x;
                    obj.plan.vhp.y;
                    table_z + 2*tol_z];
                V = [V1,V2,V3,V4]';
                text(table_center-table_x,obj.plan.vhp.y,table_z+2*tol_z-0.05,'VHP')
                fill3(V(:,1),V(:,2),V(:,3),[0 0.7 0.3],'FaceAlpha',0.2);
            end
            
            % change view angle
            az = -81.20; % azimuth
            el = 16.40; % elevation
            % angles manually tuned
            view(az,el);
            
            
        end
        
        % update the animation for robot and the ball
        function updateAnimation(obj,q)
            
            % ANIMATE BOTH THE ROBOT AND THE BALL
            b = obj.ball;
            rob = obj.robot;
            hball = obj.handle.ball;
            hrobotJ = obj.handle.robot.joints;
            hrobotE = obj.handle.robot.endeff;
            hrobotR = obj.handle.robot.racket;
            [joint,ee,racket] = rob.drawPosture(q);
            endeff = [joint(end,1:3);ee];
    
            % ball
            set(hball,'XData',b.pos(1) + b.MESH.X);
            set(hball,'YData',b.pos(2) + b.MESH.Y);
            set(hball,'ZData',b.pos(3) + b.MESH.Z);

            % robot joints
            set(hrobotJ,'XData',joint(:,1));
            set(hrobotJ,'YData',joint(:,2));
            set(hrobotJ,'ZData',joint(:,3));
            % robot endeffector
            set(hrobotE,'XData',endeff(:,1));
            set(hrobotE,'YData',endeff(:,2));
            set(hrobotE,'ZData',endeff(:,3));
            % robot racket
            set(hrobotR,'XData',racket(1,:));
            set(hrobotR,'YData',racket(2,:));
            set(hrobotR,'ZData',racket(3,:));

            drawnow;
            %pause(0.001);
            
            % this part is to draw table tennis constraints
%             loadTennisTableValues();
%             if abs(b.pos(2) - (dist_to_table-table_length/2)) < 2e-2
%                 %obj.drawNetLandConstraints();
%                 disp('comes here!');
%             end
            
            if obj.handle.record
                frame = getframe(gcf);
                writeVideo(obj.handle.recordFile,frame);
            end

            
        end
        
        % Draw feasible net and landing areas in fill3
        function drawNetLandConstraints(obj) 
            
            tol_z = 0.3;
            loadTennisTableValues();
            V1 = [table_center - table_x; 
                dist_to_table-table_length/2;
                table_z + net_height];
            V2 = [table_center + table_x;
                dist_to_table-table_length/2;
                table_z + net_height];
            V3 = [table_center + table_x;
                dist_to_table-table_length/2;
                table_z + 4*tol_z];
            V4 = [table_center - table_x;
                dist_to_table-table_length/2;
                table_z + 4*tol_z];
            V = [V1,V2,V3,V4]';
            fill3(V(:,1),V(:,2),V(:,3),[0 0.7 0.3],'FaceAlpha',0.2);
            
            H1 = [table_center - table_x;
                  dist_to_table-table_length/2;
                  table_z];
            H2 = [table_center + table_x;
                  dist_to_table-table_length/2;
                  table_z];
            H3 = [table_center + table_x;
                  dist_to_table-table_length;
                  table_z];
            H4 = [table_center - table_x;
                  dist_to_table-table_length;
                  table_z];
            H = [H1,H2,H3,H4]';
            fill3(H(:,1),H(:,2),H(:,3),[0 0.7 0.7],'FaceAlpha',0.8);
            
        end
        
    end
    
    
    
    
    
    
    
    
    
    
    
    
    
    
end