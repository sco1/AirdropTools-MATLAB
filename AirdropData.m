classdef (Abstract) AirdropData < handle & matlab.mixin.Copyable
    % Top level class definition for various helper methods
    % e.g. Data windowing, trimming, etc. so we're not copy/pasting things
    % between class definitions
    properties
    end
    
    methods (Static)
        function [date] = getdate()
            % Generate UTC time
            % ISO 8601: yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
            if ~verLessThan('MATLAB', '8.4')  % datetime added in R2014b
                timenow = datetime('now', 'TimeZone', 'UTC');
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SSZ');
            else
                UTCoffset = -java.util.Date().getTimezoneOffset/60;  % See what Java thinks your TZ offset is
                timenow = clock;
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SSZ');
            end
            
            date = string(datestr(timenow, formatstr));
        end
        
        
        function [nlines] = countlines(filepath)
            % COUNTLINES counts the number of lines present in the 
            % specified file, filepath, passed as an absolute path.
            fID = fopen(filepath, 'rt');
            
            blocksize = 16384;  % Size of block to read in, bytes
            nlines = 0;
            while ~feof(fID)
                % Read in CSV file as binary file in chunks, count the
                % number of line feed characters (ASCII 10)
                nlines = nlines + sum(fread(fID, blocksize, 'char') == char(10));
            end
            
            fclose(fID);
        end
        
        
        function [dataidx] = windowdata(ls, waitboxBool)
            % WINDOWDATA generates two draggable vertical lines in the 
            % parent axes of the input lineseries, ls, for the user to
            % use to window the data plotted with the lineseries.
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            h.ls = ls;
            h.ax = h.ls.Parent;
            h.fig = h.ax.Parent;
            
            oldbuttonup = h.fig.WindowButtonUpFcn;  % Store existing WindowButtonUpFcn
            h.fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback
            
            % Create our window lines, set the default line X locations at
            % 25% and 75% of the axes limits
            currxlim = xlim(h.ax);
            axeswidth = currxlim(2) - currxlim(1);
            leftx = axeswidth*0.25;
            rightx = axeswidth*0.75;
            h.dragline(1) = line(ones(1, 2)*leftx, ylim(h.ax), 'Color', 'g', ...
                                 'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, h));
            h.dragline(2) = line(ones(1, 2)*rightx, ylim(h.ax), 'Color', 'g', ...
                                 'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, h));
            
            % Add a background patch to highlight the currently windowed region
            currylim = ylim(h.ax);
            vertices = [leftx,  currylim(1); ...  % Bottom left corner
                        rightx, currylim(1); ...  % Bottom right corner
                        rightx, currylim(2); ...  % Top right corner
                        leftx,  currylim(2)];     % Top left corner
            h.bgpatch = patch('Vertices', vertices, 'Faces', [1 2 3 4], ...
                              'FaceColor', 'green', 'FaceAlpha', 0.05, 'EdgeColor', 'none');
            uistack(h.bgpatch, 'bottom');  % Make sure we're not covering the draglines
            listen.patchx = addlistener(h.dragline, 'XData', 'PostSet', @(s,e)AirdropData.updatebgpatch(h));
            listen.patchy = addlistener(h.dragline, 'XData', 'PostSet', @(s,e)AirdropData.updatebgpatch(h));
            
            % Add appropriate listeners to the X and Y axes to ensure
            % window lines are visible and the appropriate height
            listen.x = addlistener(h.ax, 'XLim', 'PostSet', @(s,e)AirdropData.checklinesx(h));
            listen.y = addlistener(h.ax, 'YLim', 'PostSet', @(s,e)AirdropData.changelinesy(h));
            
            % Unless passed a secondary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 2 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Window Region of Interest, Then Press OK'))
            end
            
            % Set output
            dataidx(1) = find(ls.XData >= h.dragline(1).XData(1), 1);
            dataidx(2) = find(ls.XData >= h.dragline(2).XData(1), 1);
            
            dataidx = sort(dataidx);
            
            % Clean up
            delete([listen.x listen.y]);
            delete([listen.patchx listen.patchy]);
            delete([h.dragline h.bgpatch]);
            h.fig.WindowButtonUpFcn = oldbuttonup;
        end


        function [dataidx] = fixedwindowdata(ls, windowlength, waitboxBool)
            % FIXEDWINDOWDATA generates a draggable rectangular patch in 
            % the parent axes of the input lineseries, ls, for the user to
            % use to window the data plotted with the lineseries. The
            % length of the data window, windowlength, is used under the
            % assumption that the input lineseries is a time vs. data plot
            % where time is in seconds.
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            ax = ls.Parent;
            fig = ax.Parent;
            
            oldbuttonup = fig.WindowButtonUpFcn;  % Store existing WindowButtonUpFcn
            fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback
            
            % TODO: Check to make sure the window width isn't wider than
            % the width of the plotted data
            
            currxlim = xlim(ax);
            currylim = ylim(ax);
            axeswidth = currxlim(2) - currxlim(1);

            leftx = axeswidth*0.25;
            rightx = leftx + windowlength;
            vertices = [leftx, currylim(1); ...   % Bottom left corner
                        rightx, currylim(1); ...  % Bottom right corner
                        rightx, currylim(2); ...  % Top right corner
                        leftx, currylim(2)];      % Top left corner
            dragpatch = patch('Vertices', vertices, 'Faces', [1 2 3 4], ...
                                'FaceColor', 'green', 'FaceAlpha', 0.05, ...
                                'ButtonDownFcn', {@AirdropData.startdragwindow, ax, ls});
                            
            % Add a listener to the XData of the drag patch to make sure
            % its width doesn't get adjusted. Seems to be triggered by the
            % data boundary check on drag, but I can't narrow down the 
            % specific issue. This mitigates the issue for now
            widthlistener = addlistener(dragpatch, 'XData', 'PostSet', @(s,e)AirdropData.checkdragwindowwidth(e, windowlength));
            
            % Unless passed a tertiary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 3 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Window Region of Interest, Then Press OK'))
            end
            
            % Set output
            dataidx(1) = find(ls.XData >= dragpatch.XData(1), 1);
            dataidx(2) = find(ls.XData >= dragpatch.XData(2), 1);
            dataidx = sort(dataidx);
            
            % Clean up
            delete(widthlistener)
            delete(dragpatch)
            fig.WindowButtonUpFcn = oldbuttonup;
        end
        
        
        function [xidx] = pickx(ls, waitboxBool)
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            h.ls = ls;
            h.ax = h.ls.Parent;
            h.fig = h.ax.Parent;
            
            oldbuttonup = h.fig.WindowButtonUpFcn;  % Store existing WindowButtonUpFcn
            h.fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback
            
            % Create our window lines, set the default line X locations at
            % 50% of the current axes limits
            currxlim = xlim(h.ax);
            axeswidth = currxlim(2) - currxlim(1);
            linex = axeswidth*0.25;
            
            h.dragline = line(ones(1, 2)*linex, ylim(h.ax), 'Color', 'g', ...
                             'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, h));
                         
            % Add appropriate listeners to the X and Y axes to ensure
            % window lines are visible and the appropriate height
            listen.x = addlistener(h.ax, 'XLim', 'PostSet', @(s,e)AirdropData.checklinesx(h));
            listen.y = addlistener(h.ax, 'YLim', 'PostSet', @(s,e)AirdropData.changelinesy(h));
            
            % Unless passed a secondary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 2 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Select Point of Interest, Then Press OK'))
            end
            
            % Set output
            xidx = find(ls.XData >= h.dragline(1).XData(1), 1);
            
            % Clean up
            delete([listen.x listen.y]);
            delete(h.dragline);
            h.fig.WindowButtonUpFcn = oldbuttonup;
        end
        
        
        function [varargout] = subdir(varargin)
            narginchk(0,1);
            nargoutchk(0,1);
            
            if nargin == 0
                folder = pwd;
                filter = '*';
            else
                [folder, name, ext] = fileparts(varargin{1});
                if isempty(folder)
                    folder = pwd;
                end
                if isempty(ext)
                    if isdir(fullfile(folder, name))
                        folder = fullfile(folder, name);
                        filter = '*';
                    else
                        filter = [name ext];
                    end
                else
                    filter = [name ext];
                end
                if ~isdir(folder)
                    error('Folder (%s) not found', folder);
                end
            end
            
            %---------------------------
            % Search all folders
            %---------------------------
            
            pathstr = AirdropData.genpath_local(folder);
            pathfolders = regexp(pathstr, pathsep, 'split');  % Same as strsplit without the error checking
            pathfolders = pathfolders(~cellfun('isempty', pathfolders));  % Remove any empty cells
            
            Files = [];
            pathandfilt = fullfile(pathfolders, filter);
            for ifolder = 1:length(pathandfilt)
                NewFiles = dir(pathandfilt{ifolder});
                if ~isempty(NewFiles)
                    fullnames = cellfun(@(a) fullfile(pathfolders{ifolder}, a), {NewFiles.name}, 'UniformOutput', false);
                    [NewFiles.name] = deal(fullnames{:});
                    Files = [Files; NewFiles];
                end
            end
            
            %---------------------------
            % Prune . and ..
            %---------------------------
            
            if ~isempty(Files)
                [~, ~, tail] = cellfun(@fileparts, {Files(:).name}, 'UniformOutput', false);
                dottest = cellfun(@(x) isempty(regexp(x, '\.+(\w+$)', 'once')), tail);
                Files(dottest & [Files(:).isdir]) = [];
            end
            
            %---------------------------
            % Output
            %---------------------------
            
            if nargout == 0
                if ~isempty(Files)
                    fprintf('\n');
                    fprintf('%s\n', Files.name);
                    fprintf('\n');
                end
            elseif nargout == 1
                varargout{1} = Files;
            end
        end
        
        
        function [userchoice] = nbuttondlg(question, buttonlabels, varargin)
            %NBUTTONDLG Generic n-button question dialog box.
            %  NBUTTONDLG(Question, ButtonLabels) creates a modal dialog box that sizes
            %  to accomodate a generic number of buttons. The number of buttons is
            %  determined by the number of elements in buttonlabels, a 1xn cell array
            %  of strings. The name of the button that is pressed is returned as a
            %  string in userchoice. NBUTTONDLG will theoretically support an infinite
            %  number of buttons. The default paramaters are optimized for 4 buttons.
            %
            %  NBUTTONDLG returns the label of the selected button as a character
            %  array. If the dialog window is closed without a valid selection the
            %  return value is empty.
            %
            %  NBUTTONDLG uses UIWAIT to suspend execution until the user responds.
            %
            %  Example:
            %
            %     UserChoice = nbuttondlg('What is your favorite color?', ...
            %                             {'Red', 'Green', 'Blue', 'Yellow'} ...
            %                             );
            %     if ~isempty(UserChoice)
            %        fprintf('Your favorite color is %s!\n', UserChoice);
            %     else
            %        fprintf('You have no favorite color :(\n')
            %     end
            %
            %  The Question and ButtonLabel inputs can be followed by parameter/value
            %  pairs to specify additional properties of the dialog box. For example,
            %  NBUTTONDLG(Question, ButtonLabels, 'DialogTitle', 'This is a Title!')
            %  will create a dialog box with the specified Question and ButtonLabels
            %  and replace the default figure title with 'This is a Title!'
            %
            %  Available Parameter/Value pairs:
            %
            %      BorderSize          Spacing between dialog box edges and button
            %                          edges.
            %                          Value is in pixels.
            %                          Default: 20 pixels
            %
            %      ButtonWidth         Width of all buttons
            %                          Value is in pixels.
            %                          Default: 80 pixels
            %
            %      ButtonHeight        Height of all buttons
            %                          Value is in pixels.
            %                          Default: 40 pixels
            %
            %      ButtonSpacing       Spacing between all buttons
            %                          Value is in pixels.
            %                          Default: 20 pixels
            %
            %      PromptTextHeight    Height of the Question text box
            %                          Value is in pixels.
            %                          Default: 20 pixels
            %
            %      DialogTitle         Dialog box figure title
            %                          Value is an nx1 character array
            %                          Default: 'Please Select an Option:'
            %
            %      DefaultButton       Default highlighted button
            %                          Value is an integer or an nx1 character array.
            %                          An attempt will be made to match the character
            %                          array to a value in ButtonLabel. If no match is
            %                          found or the integer value is greater than the
            %                          number of buttons the default value will be used
            %                          Default: 1
            %
            %      CancelButton        Include a cancel button. If true, a 'Cancel'
            %                          button label is added to ButtonLabel.
            %                          If 'Cancel' is selected, NBUTTONDLG returns an
            %                          empty string.
            %                          Value is true/false
            %                          Default: false
            %
            %  See also QUESTDLG, DIALOG, ERRORDLG, HELPDLG, INPUTDLG,
            %           LISTDLG, WARNDLG, UIWAIT
            
            p = generateparser;
            parse(p, varargin{:});
            
            if ~p.Results.CancelButton
                nbuttons = length(buttonlabels);
            else
                nbuttons = length(buttonlabels) + 1;
                buttonlabels{end + 1} = 'Cancel';
            end
            
            stringspacer = floor(1.5*p.Results.BorderSize); % Spacing between prompt text and buttons, pixels
            prompttxtxpos = p.Results.BorderSize; % Prompt text x position, pixels
            prompttxtypos = p.Results.BorderSize + p.Results.ButtonHeight + stringspacer; % Prompt text y position, pixels
            
            % Calculate size of entire dialog box
            dialogwidth  = 2*p.Results.BorderSize + nbuttons*p.Results.ButtonWidth + (nbuttons - 1)*p.Results.ButtonSpacing;
            dialogheight = 2*p.Results.BorderSize + p.Results.ButtonHeight + stringspacer + p.Results.PromptTextHeight;
            prompttxtwidth  = dialogwidth - 2*p.Results.BorderSize; % Prompt text width, pixels
            
            % Center window on screen
            screz = get(0, 'ScreenSize');
            boxposition = [screz(3) - dialogwidth, (screz(4) - dialogheight)]/2;
            
            dlg.mainfig = figure( ...
                'Units', 'pixels', ...
                'Position', [boxposition(1) boxposition(2) dialogwidth dialogheight], ...
                'Menubar', 'none', ...
                'Name', p.Results.DialogTitle, ...
                'NumberTitle', 'off', ...
                'ToolBar', 'none', ...
                'Resize' , 'off' ...
                );
            
            dlg.prompttxt = uicontrol( ...
                'Style', 'text', ...
                'Parent', dlg.mainfig, ...
                'Units', 'pixels', ...
                'Position', [prompttxtxpos prompttxtypos prompttxtwidth p.Results.PromptTextHeight], ...
                'String', question ...
                );
            
            % Generate and space buttons
            for ii = 1:nbuttons
                xpos = p.Results.BorderSize + (ii-1)*p.Results.ButtonSpacing + (ii-1)*p.Results.ButtonWidth;
                
                dlg.button(ii) = uicontrol( ...
                    'Style', 'pushbutton', ...
                    'Parent', dlg.mainfig, ...
                    'Units', 'pixels', ...
                    'Position', [xpos p.Results.BorderSize p.Results.ButtonWidth p.Results.ButtonHeight], ...
                    'String', buttonlabels{ii}, ...
                    'Callback', {@dlgbuttonfcn}...
                    );
            end
            
            function dlgbuttonfcn(source, ~)
                % On button press, find which button the user pressed and exit
                % function
                if ~verLessThan('MATLAB', '8.4') % handle graphics changed in R2014b
                    userchoice = buttonlabels{find(strcmp(source.String, buttonlabels), 1)};
                else
                    userchoice = buttonlabels{find(strcmp(get(source, 'String'), buttonlabels), 1)};
                end
                close(dlg.mainfig)
            end
            
            % Set default button highlighting
            if ischar(p.Results.DefaultButton)
                % Case insensitive search of the button labels for the specified button
                % string. If found, use that as the default button. Otherwise default
                % to the first button.
                
                if sum(strcmpi(p.Results.DefaultButton, buttonlabels)) ~= 0
                    DefaultButton = find(strcmpi(p.Results.DefaultButton, buttonlabels), 1);
                else
                    DefaultButton = 1;
                end
            elseif isnumeric(p.Results.DefaultButton)
                % Round to the nearest integer, use that as the default button. If it's
                % greater than the number of buttons, default to the first button. If
                % an array of numbers is presented, pick the first one.
                DefaultButton = round(p.Results.DefaultButton);
                if DefaultButton > nbuttons
                    DefaultButton = 1;
                end
            else
                % Default to first button
                DefaultButton = 1;
            end
            setdefaultbutton(dlg.button(DefaultButton));
            
            waitfor(dlg.mainfig);
            
            if ~exist('userchoice', 'var')
                % Dialog was closed without making a selection
                % Mimic questdlg behavior and return an empty string
                userchoice = '';
            end
            
            if p.Results.CancelButton && strcmp('Cancel', userchoice)
                % Cancel button selected, return an empty string
                userchoice = '';
            end
        end
        
        
        function setdefaultbutton(btnHandle)
            % Helper function ripped from questboxdlg
            
            % First get the position of the button.
            if ~verLessThan('MATLAB', '8.4') % handle graphics changed in R2014b
                buttonunits = btnHandle.Units;
            else
                buttonunits = get(btnHandle, 'Units');
            end
            
            if strcmp(buttonunits, 'Pixels')
                btnPos = btnHandle.Position;
            else
                if ~verLessThan('MATLAB', '8.4') % handle graphics changed in R2014b
                    oldunits = btnHandle.Units;
                    btnHandle.Units = 'Pixels';
                    btnPos = btnHandle.Position;
                    btnHandle.Units = oldunits;
                else
                    oldunits = get(btnHandle, 'Units');
                    set(btnHandle, 'Units', 'Pixels');
                    btnPos = get(btnHandle, 'Position');
                    set(btnHandle, 'Units', oldunits);
                end
            end
            
            % Next calculate offsets.
            leftOffset   = btnPos(1) - 1;
            bottomOffset = btnPos(2) - 2;
            widthOffset  = btnPos(3) + 3;
            heightOffset = btnPos(4) + 3;
            
            % Create the default button look with a uipanel.
            % Use black border color even on Mac or Windows-XP (XP scheme) since
            % this is in natve figures which uses the Win2K style buttons on Windows
            % and Motif buttons on the Mac.
            h1 = uipanel(get(btnHandle, 'Parent'), 'HighlightColor', [0 0 0.8], ...
                'BorderType', 'etchedout', 'units', 'pixels', ...
                'Position', [leftOffset bottomOffset widthOffset heightOffset]);
            
            % Make sure it is stacked on the bottom.
            uistack(h1, 'bottom');
        end
        
        
        function p = generateparser
            p = inputParser;
            
            defaultbordersize      = 20; % Border size, pixels
            defaultbuttonwidth     = 80; % Button width, pixels
            defaultbuttonheight    = 40; % Button height, pixels
            defaultbuttonspacing   = 20; % Spacing between buttons, pixels
            defaultprompttxtheight = 20; % Prompt text height, pixels
            defaultdialogtitle = 'Please Select an Option:'; % Dialog box title, string
            defaultbutton = 1;  % Button selected by default, integer
            includecancelbutton = false; % Include cancel button, logical
            
            addOptional(p, 'BorderSize', defaultbordersize, @isnumeric);
            addOptional(p, 'ButtonWidth', defaultbuttonwidth, @isnumeric);
            addOptional(p, 'ButtonHeight', defaultbuttonheight, @isnumeric);
            addOptional(p, 'ButtonSpacing', defaultbuttonspacing, @isnumeric);
            addOptional(p, 'PromptTextHeight', defaultprompttxtheight, @isnumeric);
            addOptional(p, 'DialogTitle', defaultdialogtitle, @ischar);
            addOptional(p, 'DefaultButton', defaultbutton); % Can be string or integer, behavior handled in main function
            addOptional(p, 'CancelButton', includecancelbutton, @islogical);
        end
        
        
        function [p] = saveargparse(varargin)
            p = inputParser();
            p.addParameter('savefilepath', '', @ischar);
            p.addParameter('saveasclass', true, @islogical);
            p.addParameter('verboseoutput', false, @islogical);
            p.parse(varargin{:});
        end
        
        
        function save(savefilepath, dataObj, isverbose, saveasclass)
            if saveasclass
                save(savefilepath, 'dataObj');
            else
                % Save property values only, not class instance
                propstosave = properties(dataObj);  % Get list of public properties
                
                for ii = 1:length(propstosave)
                    prop = propstosave{ii};
                    tmp.(prop) = dataObj.(prop);
                end

                save(savefilepath, '-struct', 'tmp');
            end

            if isverbose
                if saveasclass
                    fprintf('%s object instance saved to ''%s''\n', class(dataObj), savefilepath);
                else
                    fprintf('%s object public properties saved to ''%s''\n', class(dataObj), savefilepath);
                end
            end
        end
        
        
        function [chkbool, idx] = matclassinstancechk(filepath, classtype)
            matfileinfo = whos('-file', filepath);
            classtest = strcmp({matfileinfo(:).class}, classtype);
            if any(classtest)
                % Only return index to first class instance
                chkbool = true;
                idx = find(classtest, 1);
            else
                chkbool = false;
                idx = [];
            end
        end
    end
    
    methods (Static, Hidden, Access = protected)
        function startdrag(draggedline, h)
            % Helper function for data windowing, sets figure
            % WindowButtonMotionFcn callback to dragline helper
            % while line is being clicked on & dragged
            h.ax.Parent.WindowButtonMotionFcn = @(s,e)AirdropData.linedrag(h.ax, draggedline, h.ls);
        end
        
        
        function stopdrag(hObj, ~)
            % Helper function for data windowing, clears figure window
            % WindowButtonMotionFcn callback when mouse button is released
            % after dragging the line
            hObj.WindowButtonMotionFcn = '';
        end
        
        
        function checklinesx(h)
            % Helper function for data windowing, checks the X indices of
            % the vertical lines to make sure they're still within the X
            % axis limits of the data axes object
            ndraglines = numel(h.dragline);
            currxlim = h.ax.XLim;
            currlinex(1) = h.dragline(1).XData(1);
            
            if ndraglines == 2
                currlinex(2) = h.dragline(2).XData(1);
            end
                        
            % Set X coordinate of any line outside the axes limits to the
            % axes limit
            if currlinex(1) < currxlim(1)
                h.dragline(1).XData = [1, 1]*currxlim(1);
            end
            
            if currlinex(1) > currxlim(2)
                h.dragline(1).XData = [1, 1]*currxlim(2);
            end
            
            if ndraglines == 2
                if currlinex(2) < currxlim(1)
                    h.dragline(2).XData = [1, 1]*currxlim(1);
                end
                
                if currlinex(2) > currxlim(2)
                    h.dragline(2).XData = [1, 1]*currxlim(2);
                end
            end
            
            % Set X coordinate of any line beyond the boundary of the
            % lineseries to the closest boundary
            minX = min(h.ls.XData);
            maxX = max(h.ls.XData);            
            if currlinex(1) < minX
                h.dragline(1).XData = [1, 1]*minX;
            end
            
            if currlinex(1) > maxX
                h.dragline(1).XData = [1, 1]*maxX;
            end
            
            if ndraglines == 2
                if currlinex(2) < minX
                    h.dragline(2).XData = [1, 1]*minX;
                end
                
                if currlinex(2) > maxX
                    h.dragline(2).XData = [1, 1]*maxX;
                end
            end
        end
        
        
        function changelinesy(h)
            % Helper function for data windowing, sets the height of both
            % vertical lines to the height of the axes object
            h.dragline(1).YData = ylim(h.ax);
            
            if ndraglines == 2
                h.dragline(2).YData = ylim(h.ax);
            end
        end

        
        function linedrag(ax, draggedline, plottedline)
            % Helper function for data windowing, updates the x coordinate
            % of the dragged line to the current location of the mouse
            % button
            currentX = ax.CurrentPoint(1, 1);
            
            % Prevent dragging outside of the current axes limits
            if currentX < ax.XLim(1)
                draggedline.XData = [1, 1]*ax.XLim(1);
            elseif currentX > ax.XLim(2)
                draggedline.XData = [1, 1]*ax.XLim(2);
            else
                draggedline.XData = [1, 1]*currentX;
            end
            
            minX = min(plottedline.XData);
            maxX = max(plottedline.XData);
            % Prevent dragging outside of the data limits
            if currentX < minX
                draggedline.XData = [1, 1]*minX;
            elseif currentX > maxX
                draggedline.XData = [1, 1]*maxX;
            end
        end
        
        
        function updatebgpatch(h)
            draglinex = sort([h.dragline(1).XData(1), h.dragline(2).XData(1)]);
            currylim = ylim(h.ax);
            h.bgpatch.Vertices = [draglinex(1) currylim(1); ...
                                  draglinex(2) currylim(1); ...
                                  draglinex(2) currylim(2); ...
                                  draglinex(1) currylim(2)];
        end
        
        
        function startdragwindow(patchObj, ed, ax, ls)
            ax.Parent.WindowButtonMotionFcn = @(s,e)AirdropData.dragwindow(ax, patchObj, ls);
            patchObj.UserData = ed.IntersectionPoint(1);  % Store initial click location to find a delta later
        end
        
        
        function dragwindow(ax, patchObj, plottedline)
            oldmouseX = patchObj.UserData;
            newmouseX = ax.CurrentPoint(1);
            patchObj.UserData = newmouseX;
            
            dx = newmouseX - oldmouseX;
            newpatchX = patchObj.XData + dx; 
          
            % Prevent dragging outside of the current axes limits
            if newpatchX(1) < ax.XLim(1)
                newdx = patchObj.XData - ax.XLim(1);
                patchObj.XData = patchObj.XData + newdx;
            elseif newpatchX(2) > ax.XLim(2)
                newdx = patchObj.XData - ax.XLim(2);
                patchObj.XData = patchObj.XData + newdx;
            else
                patchObj.XData = newpatchX;
            end
            
            % Prevent dragging beyond the limits of the plotted lineseries
            minX = min(plottedline.XData);
            maxX = max(plottedline.XData);
            if newpatchX(1) < minX
                newdx = patchObj.XData(1) - minX;  % Subtract from left boundary only
                patchObj.XData = patchObj.XData - newdx;
            elseif newpatchX(2) > maxX
                newdx = patchObj.XData(2) - maxX;  % Subtract from right boundary only
                patchObj.XData = patchObj.XData - newdx;
            end
        end
        
        
        function checkdragwindowwidth(ed, width)
            % Check the width of the drag patch to make sure it doesn't get
            % adjusted. For a still-unknown reason there is a scenario where
            % the width of the patch grows unbounded. It seems to be 
            % triggered by the data boundary check on drag.
            badwidth = abs(ed.AffectedObject.XData(1) - ed.AffectedObject.XData(2)) ~= width;
            if badwidth
                ed.AffectedObject.XData(2:3) = [1, 1]*ed.AffectedObject.XData(1) + width;
            end
        end
        
        
        function [p] = genpath_local(d)
            % Modified genpath that doesn't ignore:
            %     - Folders named 'private'
            %     - MATLAB class folders (folder name starts with '@')
            %     - MATLAB package folders (folder name starts with '+')
            
            files = dir(d);
            if isempty(files)
                return
            end
            p = '';  % Initialize output
            
            % Add d to the path even if it is empty.
            p = [p d pathsep];
            
            % Set logical vector for subdirectory entries in d
            isdir = logical(cat(1,files.isdir));
            dirs = files(isdir);  % Select only directory entries from the current listing
            
            for i=1:length(dirs)
                dirname = dirs(i).name;
                if    ~strcmp( dirname,'.') && ~strcmp( dirname,'..')
                    p = [p genpath(fullfile(d,dirname))];  % Recursive calling of this function.
                end
            end
        end
    end
end