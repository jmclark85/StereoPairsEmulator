classdef StereoPairsEmulator < audioPlugin
    %STEREOPAIRSEMULATOR Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        % These are in radians, for calculations
        tML; %theta value for main left
        tMR; %theta value for main right
        tFL; % theta value for flank left
        tFR; % theta value for flank right
        % These are in degrees, for UI
        splayM; %angular splay value for the mains
        splayF; %angular splay value for the flanks
        % Some number from 0 to 1
        pM; %P value for the mains
        pF; %P value for the flanks
        pC; %P value for the center mic (should match mains... but people are weird)
        % These are in cm for UI
        distanceM; % lateral offset for mains
        distanceF; % lateral offset between the flanks
        distanceC; %forward offset of the center mic
        % Toggles to use or ignore certain mics
        toggleC; % use center
        toggleF; % use flanks
        toggleM; % use mains
        % Audio level adjustments, so we can mixdown the 5 channels to 2 in
        % the vst and maintain the 2x2 restriction; ideally the option
        % would be present to output 5 channels for further mixing
        levelM; % level for mains
        levelF; % level for flanks
        levelC; % level for center
        % Sound source settings
        thetaS; % angle of source, in radians
        s; % source angle, in degrees, input for UI
        dS; % distance of source, in meters, input for UI
        sX; % x value of source
        sY; % y value of source
        % x-coordinate values (converting to meters as the unit distance)
        % for the virtual microphones
        xML;
        xMR;
        xFL;
        xFR;
        yC;
        %---
        % NB: Channel ordering is LM RM LF RF C
        dtArray; % For holding time delay values
        ampArray; % For holding amplitude scalar values
        recalcFlag; % It is not expected that the user will frequently change the UI values once they are set. So, continually calculating the spatial data is a waste of CPU. This flag will notify the plugin that a change was made.
        dlyCompEnable; % Toggle to trigger the use of distance-based delay compensation.
        cAdjust; % This is a user-adjustable offset to the speed of sound.
    end
    properties(Access = private)
        sampleRate = 48000; % default sample rate
        delayLine;        
    end
    properties(Constant)
        PluginInterface = audioPluginInterface(...
            'PluginName','Stereo Pairs Emulator',...
            'VendorName','Fat Penguin Sound',...
            'VendorVersion', '0.0.2',...
            'InputChannels',1,...
            'OutputChannels',2,...
            audioPluginParameter('s',...
                'DisplayName','Source Angle',...
                'Mapping',{'lin',-90,90},... % This will need to be flipped in calculations... also converted to radians.
                'Style','rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','�'),...
            audioPluginParameter('dS',...
                'DisplayName','Panning',...
                'Mapping',{'lin',0,15},... % This is in meters -- controls the maximum distance the source can be away from the center of the main array
                'Style','rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','m'...
            ),...
            audioPluginParameter('distanceM',...
                'DisplayName','Distance',...
                'Mapping',{'lin',0,200},... % Distance between the main stereo pair. Needs to be converted to m for calculations.
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','cm'...
            ),...
            audioPluginParameter('distanceF',...
            'DisplayName','Distance',...
                'Mapping',{'lin',0,10},... % Distance between the flanking stereo pair. This distance is in meters.
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','m'...
            ),...
            audioPluginParameter('distanceC',...
                'DisplayName','Distance',...
                'Mapping',{'lin',0,200},... % Distance of the centre mic (forward). In cm and needs to be converted.
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','cm'...
            ),...
            audioPluginParameter('splayM',...
                'DisplayName','Angle',...
                'Mapping',{'lin',0,180},... % Angle between the microphones in degrees
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','�'...
            ),...
            audioPluginParameter('splayF',...
                'DisplayName','Angle',...
                'Mapping',{'lin',0,180},... % Angle between the microphones in degrees
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','�'...
            ),...
            audioPluginParameter('pM',...
                'DisplayName','Directivity',...
                'Mapping',{'lin',0,1},... % We'll make this so that it increases directivity as it moves towards 1, that'll make more sense for the user
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above'...
            ),...
            audioPluginParameter('pF',...
                'DisplayName','Directivity',...
                'Mapping',{'lin',0,1},... 
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above'...
            ),...
            audioPluginParameter('pC',...
                'DisplayName','Directivity',...
                'Mapping',{'lin',0,1},... 
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above'...
            ),...
            audioPluginParameter('levelM',...
                'DisplayName','Level',...
                'Mapping',{'pow',1/3,-20,0},... % This range could be wider, but for mixing, this is probably the most realistically useful range. Any lower than -20 and the mics should just be turned off.
                'Style','vslider',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','dB'...
            ),...
            audioPluginParameter('levelF',...
                'DisplayName','Level',...
                'Mapping',{'pow',1/3,-20,0},...
                'Style','vslider',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','dB'...
            ),...
            audioPluginParameter('levelC',...
                'DisplayName','Level',...
                'Mapping',{'pow',1/3,-20,0},...
                'Style','vslider',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','dB'...
            ),...
            audioPluginParameter('toggleM',...
                'DisplayName','Mains',...
                'Style','vrocker',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above'...
            ),...
            audioPluginParameter('toggleF',...
                'DisplayName','Flanks',...
                'Style','vrocker',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above'...
            ),...
            audioPluginParameter('toggleC',...
                'DisplayName','Centre',...
                'Style','vrocker',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above'...
            ),...
            audioPluginParameter('cAdjust',...
                'DisplayName','Time Alignment',...
                'Mapping',{'lin',-10,10},... % Based on an estimate of temperture values on a concert hall, giving a range of speed of sound values for potential tempertures.
                'Style','Rotaryknob',...
                'Layout',[1,1],...
                'DisplayNameLocation','Above',...
                'Label','m/s'...                
            ),...
            audioPluginGridLayout( ...
                'RowHeight',[20, 100, 20, 20, 100, 20, 100, 20, 160],...
                'ColumnWidth',[50, 50, 50, 50, 100, 50, 50, 50, 50])...
        );
    end
    properties(Constant)%Some convenience numbers
        hpi = pi/2;
        c = 343;
        sq2 = sqrt(2);
        radConv = pi / 180; % convenience for converting degrees to radians
        cm2m = 1 / 100; % convenience for converting cm to m
        thetaC = 0; % theta value for the center mic, will always be forward
        % Some static positional numbers, to make things more consistent
        % and readable. Since the main and flank mics will never move off
        % the x axis their y values can just be assumed to be 0:
        yML = 0;
        yMR = 0;
        yFL = 0;
        yFR = 0;
        xC = 0; % Since the centre mic only moves front back.
    end
    
    methods
        function plugin = StereoPairsEmulator %This is the constructor for the plugin            
            plugin.delayLine = dsp.VariableIntegerDelay(... % The VID needs to be initialised here in the constructor
            'MaximumDelay', 11520,... % 60ms @ 192kHz
            'InitialConditions',0 ...
        ); 
        end
        function out = process(plugin, in) %actual processing here
            
            
        end
        % A whole bunch of setters for the UI tunable parameters
        function set.dS(plugin, val)
            plugin.dS = val;
            plugin.recalcFlag = 1; % Ignore the warning that MatLab throws here (per Mathworks plugin website). This will cause the intermediary values to be recalculated.
                                   % See : https://www.mathworks.com/help/audio/ug/tips-and-tricks-for-plugin-authoring.html#bvnoc85-1 for more information about the error and why we can ignore it. 
        end
        function set.s(plugin,val)
            plugin.s = val;
            plugin.recalcFlag = 1;
        end
        function set.distanceM(plugin,val)
            plugin.distanceM = val;
            plugin.recalcFlag = 1;
        end
        function set.distanceF(plugin,val)
            plugin.distanceF = val;
            plugin.recalcFlag = 1;
        end
        function set.distanceC(plugin,val)
            plugin.distanceC = val;
            plugin.recalcFlag = 1;
        end
        function set.splayM(plugin,val)
            plugin.splayM = val;
        end
        function set.splayF(plugin,val)
            plugin.splayF = val;
            plugin.recalcFlag = 1;
        end
        function set.pM(plugin,val)
            plugin.pM = val;
            plugin.recalcFlag = 1;
        end
        function set.pF(plugin,val)
            plugin.pF = val;
            plugin.recalcFlag = 1;
        end
        function set.pC(plugin,val)
            plugin.pC = val;
            plugin.recalcFlag = 1;
        end
        function set.levelM(plugin,val) % The rest of these don't need to retrigger the virtual mic calculations
            plugin.levelM = val;
        end
        function set.levelF(plugin,val)
            plugin.levelF = val;
        end
        function set.levelC(plugin,val)
            plugin.levelC = val;
        end
        function set.toggleM(plugin,val)
            plugin.toggleM=val;
        end
        function set.toggleF(plugin,val)
            plugin.toggleF=val;
        end
        function set.toggleC(plugin,val)
            plugin.toggleC=val;
        end
        function reset(plugin) % Reset the plugin
            plugin.recalcFlag = 1; % Set plugin to recalculate spatial data
            plugin.sampleRate = getSampleRate(plugin); % Get the sample rate
            reset(plugin.delayLine); % Reinitialise the delay line
        end
    end
    methods(Static) % Convenience methods to simplify and segment the code
        function m = virtualMic(thetaMic, thetaSource, directivity) % This returns a scalar coeffcient based on the polar pattern and how "off-axis" the source is to the virtual microphone
            o = (1 - directivity) * sq2;
            b = directivity * cos(thetaMic - thetaSource);
            m = o + b;
        end
        function t = splayConv(splay) % Converts the angular splay into a radian offset amount. Note that the angular splay is the angle between the virtual mics, so the offset amount needs to be half the splay.
            t = (splay * plugin.radConv) / 2;
        end
        function setTheta(plugin) % Sets the theta for the main and flank mics.
            % Convert the splays to radian values offset from forward
            tM = splayConv(plugin.splayM);
            tF = splayConv(plugin.splayF);
            % Set the microphones angles, left mics angle with a positive
            % rotation and right mics angle with a negative rotation away
            % from "forward"
            plugin.tML = tM + plugin.hpi; % Half-pi rotation so that the y-axis is "forward". 
            plugin.tMR = -tM + plugin.hpi;
            plugin.tFL = tF + plugin.hpi;
            plugin.tFR = -tF + plugin.hpi;
            %Convert the source from degrees to radians, also need to flip
            %it since -90 is leftward rotation. 
            plugin.thetaS = (-1 * plugin.s) * plugin.radConv + plugin.hpi;
        end
        function setCartCoord(plugin) % Fills in the cartesian coordinates for the virtual mics
            % Intermediary calculations and unit conversions
            dM = (plugin.distanceM / 2) * cm2m;
            dF = plugin.distanceF / 2;
            % Setters left microphones move -x and right microphones move
            % +x
            plugin.xML = -dM;
            plugin.xMR = dM;
            plugin.xFL = -dF;
            plugin.xFR = dF;
            plugin.yC = plugin.distanceC * cm2m;
            % Get the source X and Y position
            plugin.sX = plugin.dS * cos(plugin.thetaS);
            plugin.sY = plugin.dS * sin(plugin.thetaS);
        end
        function setAmpArray(plugin) % Feeds the correct amplitude scalar coefficients into the ampArray.
            % Get the angle of the source relative to each microphone
            tSML = atan2(plugin.sY - plugin.yML, plugin.sX - plugin.xML );
            tSMR = atan2(plugin.sY - plugin.yMR, plugin.sX - plugin.xMR );
            tSFL = atan2(plugin.sY - plugin.yFL, plugin.sX - plugin.xFL );
            tSFR = atan2(plugin.sY - plugin.yFR, plugin.sX - plugin.xFR );
            tSC = atan2(plugin.sY - plugin.yC, plugin.sX - plugin.xC );
            % Find the individual amp modifiers
            ml = plugin.virtualMic(plugin.thetaML, tSML, plugin.pM);
            mr = plugin.virtualMic(plugin.thetaMR, tSMR, plugin.pM);
            fl = plugin.virtualMic(plugin.thetaFL, tSFL, plugin.pF);
            fr = plugin.virtualMic(plugin.thetaFR, tSFR, plugin.pF);
            cent = plugin.virtualMic(plugin.thetaC, tSC, plugin.pC);
            % Set the values in the array
            plugin.ampArray = [ml mr fl fr cent];         
        end
        function d = calculateDistance (mx, my, sx, sy) % Returns the distance between points m and s.
             x = (sx - mx)^2;
             y = (sy - my)^2;
             d = sqrt(x + y);
        end
        function t = distTimeConvert (d, sos) % Converts a distance to a time
            t = d / sos;
        end
        function setDTArray(plugin) % Sets the delay times in dtArray
            % Calculate distances from the source to each virtual mic
            dML = plugin.calculateDistance(plugin.xML, plugin.yML, plugin.sX, plugin.sY);
            dMR = plugin.calculateDistance(plugin.xMR, plugin.yMR, plugin.sX, plugin.sY);
            dFL = plugin.calculateDistance(plugin.xFL, plugin.yFL, plugin.sX, plugin.sY);
            dFR = plugin.calculateDistance(plugin.xFR, plugin.yFR, plugin.sX, plugin.sY);
            dC = plugin.calculateDistance(plugin.xC, plugin.yC, plugin.sX, plugin.sY);
            % Convert the distances to a time
            sos = plugin.c + plugin.cAdjust;
            tML = plugin.distTimeConvert(dML, sos);
            tMR = plugin.distTimeConvert(dMR, sos);
            tFL = plugin.distTimeConvert(dFL, sos);
            tFR = plugin.distTimeConvert(dFR, sos);
            tC = plugin.distTimeConvert(dC, sos);
            % Add to the array
            plugin.dtArray = [tML tMR tFL tFR tC];
            plugin.dtArray = plugin.dtArray * plugin.sampleRate; % Convert to samples
        end
        function removeDelayComp(plugin) % This function removes the delay compensation by finding the smalles value in dtArray and subtracting that value from every element in dtArray
            plugin.dtArray = plugin.dtArray - min(plugin.dtArray);       
        end
        
    end
end

